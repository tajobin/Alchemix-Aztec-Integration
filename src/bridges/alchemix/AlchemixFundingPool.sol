// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IAlchemistV2} from "../../interfaces/alchemix/IAlchemistV2.sol";

import "forge-std/console2.sol";

contract AlchemixFundingPool is ERC20 {
    address public immutable BENEFICIARY; // The address that will be funded by this pool
    address private immutable BRIDGE_ADDRESS;
    address public immutable YTOKEN;
    address public immutable UNDERLYING_TOKEN;
    address public immutable ALTOKEN; 
    address private immutable ALCHEMIST; 
    uint256 private immutable INITIAL_COL;

    constructor(
        address _bridgeAddress, 
        address _yToken,
        address _underlyingToken,
        address _alchemist,
        address _alToken,
        address _beneficiary,
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
        BENEFICIARY = _beneficiary;
    }

    function mint (address _account, uint256 _amount) internal {
        _mint(_account, _amount);
    }

    function burn (address _account, uint256 _amount) internal {
        _burn(_account, _amount);
    }

    function depositAndMint(uint256 _amountDeposit) external returns (uint256 shares){
        require(msg.sender == BRIDGE_ADDRESS);

        uint256 col; int256 debt; uint256 collateral; uint256 tokenPerShare;
        if (totalSupply() == 0){
            col = INITIAL_COL; 
        } else {
            (col, debt, collateral, tokenPerShare) = _getPoolInfo();
        }

        if (col > INITIAL_COL){ // Yield accrued that partially goes to the beneficiary

            uint256 newYield = collateral*1e18/INITIAL_COL - uint256(debt); 
            uint256 amountMint = newYield + _amountDeposit*1e18/INITIAL_COL;  

            IERC20(UNDERLYING_TOKEN).approve(ALCHEMIST, _amountDeposit);

            uint256 expectedShares = _amountDeposit*1e18/tokenPerShare;
            shares = IAlchemistV2(ALCHEMIST).depositUnderlying(
                YTOKEN, 
                _amountDeposit, 
                address(this), 
                expectedShares*0.98e18/1e18  
            ); 

            // Mint
            IAlchemistV2(ALCHEMIST).mint(amountMint, BENEFICIARY); //minting alUSD to the bridge,
            mint(BRIDGE_ADDRESS, shares); //minting shareToken to bridge. 

        } else {  // No new yield to send to beneficiary

            tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);
            uint256 amountMint = _amountDeposit*1e18/col;  
            // Deposit and get shares
            IERC20(UNDERLYING_TOKEN).approve(ALCHEMIST, _amountDeposit);

            uint256 expectedShares = _amountDeposit*1e18/tokenPerShare;
            shares = IAlchemistV2(ALCHEMIST).depositUnderlying(
                YTOKEN, 
                _amountDeposit, 
                address(this), 
                expectedShares*0.98e18/1e18  
            ); 

            // Mint
            IAlchemistV2(ALCHEMIST).mint(amountMint, BENEFICIARY); //mint to beneficiary 
            mint(BRIDGE_ADDRESS, shares); //minting shareToken to bridge. 
        }
    }

    function repayAndWithdraw(uint256 _sharesDeposited) external returns (uint256 daiWithdrawn) {
        require(msg.sender == BRIDGE_ADDRESS);

        if (totalSupply() == 0){
            revert("Empty pool");
        }

        (uint256 col, int256 debt, uint256 collateral, uint256 tokenPerShare) = _getPoolInfo();

        if (col/1e14 > INITIAL_COL/1e14){ //There is yield to be payed to the beneficiary
            uint256 newYield = collateral*1e18/INITIAL_COL - uint256(debt); // Amount of Yield belonging to beneficiary
            IAlchemistV2(ALCHEMIST).mint(newYield, BENEFICIARY); //minting alUSD to the bridge, col should be == INITIAL now

            uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);
            uint256 underlyingTokenAmount = _sharesDeposited*tokenPerShare/1e18;  
            uint256 debtToCover = underlyingTokenAmount*1e18/INITIAL_COL; 
            uint256 debtToCoverInShares = debtToCover*1e18/tokenPerShare; //@note rounding

            uint256 sharesLiquidated = IAlchemistV2(ALCHEMIST).liquidate(
                YTOKEN, 
                debtToCoverInShares, 
                debtToCoverInShares*0.999e18/1e18
            );

            uint256 expectedSharesBack = _sharesDeposited-sharesLiquidated - 100;

            daiWithdrawn = IAlchemistV2(ALCHEMIST).withdrawUnderlying(
                YTOKEN, 
                expectedSharesBack, 
                BRIDGE_ADDRESS, 
                expectedSharesBack*0.999e18/1e18
            );
        } 
        else { // No yield to send to the beneficiary
            uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);
            uint256 underlyingTokenAmount = _sharesDeposited*tokenPerShare/1e18;  
            uint256 debtToCover = underlyingTokenAmount*1e18/col + 1; 
            uint256 debtToCoverInShares = debtToCover*1e18/tokenPerShare + 1; 

            uint256 sharesLiquidated = IAlchemistV2(ALCHEMIST).liquidate(
                YTOKEN, 
                debtToCoverInShares, 
                debtToCoverInShares*0.999e18/1e18
            );

            uint256 expectedSharesBack = _sharesDeposited-sharesLiquidated - 100;

            daiWithdrawn = IAlchemistV2(ALCHEMIST).withdrawUnderlying(
                YTOKEN, 
                expectedSharesBack, 
                BRIDGE_ADDRESS, 
                expectedSharesBack*0.999e18/1e18
            );
        }
    }

    function _getCollateralization() internal returns (uint256 col){
        IAlchemistV2(ALCHEMIST).poke(address(this));
        uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);

        (int256 debt, ) = IAlchemistV2(ALCHEMIST).accounts(address(this)); // @note correct way to get debt after poke?
        (uint256 shares, ) = IAlchemistV2(ALCHEMIST).positions(address(this), YTOKEN); // @note same for shares 

        uint256 tokenAmount = tokenPerShare*shares/1e18; // @note check on rounding
        col = tokenAmount*1e18/uint256(debt); 
    }
    
    function _getPoolInfo() internal returns (uint256 collateralization, int256 debt, uint256 collateral, uint256 tokenPerShare){
        IAlchemistV2(ALCHEMIST).poke(address(this));
        tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YTOKEN);

        (debt, ) = IAlchemistV2(ALCHEMIST).accounts(address(this)); // @note correct way to get debt after poke?
        (uint256 shares, ) = IAlchemistV2(ALCHEMIST).positions(address(this), YTOKEN); // @note same for shares 

        collateral = tokenPerShare*shares/1e18; // @note check on rounding
        collateralization = collateral*1e18/uint256(debt); 
    }
}