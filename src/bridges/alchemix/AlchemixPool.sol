// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IAlchemistV2} from "../../interfaces/alchemix/IAlchemistV2.sol";

import "forge-std/console2.sol";

contract AlchemixPool is ERC20 {
    error InvalidDepositAmount();

    address private immutable BRIDGE_ADDRESS;
    address public immutable YTOKEN;
    address public immutable UNDERLYING_TOKEN;
    address public immutable ALTOKEN; 
    address public immutable ALCHEMIST; 
    uint256 private immutable INITIAL_COL;

    constructor(
        address _bridgeAddress, 
        address _yToken,
        address _underlyingToken,
        address _alchemist,
        address _alToken,
        uint256 _initialCol,
        string memory name_, 
        string memory symbol_
        ) 
        ERC20(name_, symbol_)
    {
        BRIDGE_ADDRESS = _bridgeAddress;
        YTOKEN = _yToken;
        UNDERLYING_TOKEN = _underlyingToken;
        INITIAL_COL = _initialCol;
        ALCHEMIST = _alchemist;
        ALTOKEN = _alToken;
    }

    function mint (address _account, uint256 _amount) internal {
        _mint(_account, _amount);
    }

    function burn (address _account, uint256 _amount) internal {
        _burn(_account, _amount);
    }

    function depositAndMint(uint256 _amountDeposit) external returns (uint256 shares, uint256 amountMint){
        require(msg.sender == BRIDGE_ADDRESS);

        (uint256 col, uint256 tokenPerShare) =  _getPoolInfo();

        amountMint = _amountDeposit*1e18/col;  
        uint256 expectedShares = _amountDeposit*1e18/tokenPerShare;

        IERC20(UNDERLYING_TOKEN).approve(ALCHEMIST, _amountDeposit);
        shares = IAlchemistV2(ALCHEMIST).depositUnderlying(
            YTOKEN, 
            _amountDeposit, 
            address(this), 
            expectedShares*0.98e18/1e18  
            // Slippage is hard coded could change so that it is set on the front-end and passed
            // to the pool by encoding it into the auxData variable.
        ); 

        IAlchemistV2(ALCHEMIST).mint(amountMint, BRIDGE_ADDRESS); //minting alUSD to the bridge,
        mint(BRIDGE_ADDRESS, shares); //minting shareToken to bridge. 

    }

    function repayAndWithdraw(uint256 _sharesDeposited) external returns (uint256 daiWithdrawn) {
        require(msg.sender == BRIDGE_ADDRESS);

        if (_sharesDeposited <= 0) revert InvalidDepositAmount();

        (uint256 col, uint256 tokenPerShare) =  _getPoolInfo();

        uint256 underlyingTokenAmount = _sharesDeposited*tokenPerShare/1e18;  
        uint256 debtToCover = (underlyingTokenAmount*1e18/col) + 1; //Round up to cover all debt
        uint256 debtToCoverInShares = (debtToCover*1e18/tokenPerShare) + 1; //Round up to cover all debt

        (int256 debtBefore, ) = IAlchemistV2(ALCHEMIST).accounts(address(this)); 

        uint256 sharesLiquidated = IAlchemistV2(ALCHEMIST).liquidate(
            YTOKEN, 
            debtToCoverInShares, 
            debtToCoverInShares*0.999e18/1e18
            // Slippage is hard coded could change so that it is set on the front-end and passed
            // to the pool by encoding it into the auxData variable.
        );

        (int256 debt, ) = IAlchemistV2(ALCHEMIST).accounts(address(this)); 

        // Subtracting 100 to leave dust so that withdrawl is possible if debt >0 is left after liquidation of all collateral
        uint256 expectedSharesBack = _sharesDeposited-sharesLiquidated-100;

        daiWithdrawn = IAlchemistV2(ALCHEMIST).withdrawUnderlying(
            YTOKEN, 
            expectedSharesBack, 
            BRIDGE_ADDRESS, 
            expectedSharesBack*0.999e18/1e18
            // Slippage is hard coded could change so that it is set on the front-end and passed
            // to the pool by encoding it into the auxData variable.
        );
    }

    function _getPoolInfo() internal returns (uint256 col, uint256 tokenPerShare){
        IAlchemistV2(ALCHEMIST).poke(address(this));
        
        if (totalSupply() == 0){
            col = INITIAL_COL; 
            tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);
        } else {
            tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);
            (int256 debt, ) = IAlchemistV2(ALCHEMIST).accounts(address(this)); 
            (uint256 shares, ) = IAlchemistV2(ALCHEMIST).positions(address(this), YTOKEN);

            uint256 tokenAmount = tokenPerShare*shares/1e18; 
            col = tokenAmount*1e18/uint256(debt); 
        }
   }
}