// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AlchemixPool} from "./AlchemixPool.sol";
import {AlchemixFundingPool} from "./AlchemixFundingPool.sol";


/**
 * @title A bridge contract for Alchemix 
 * @author Tajobin 
 * @dev This bridge is built to integrate Alchemix with aztec-connect 
 *      
 */
contract AlchemixBridge is BridgeBase {
    address public immutable ADMIN;

    address[] public pools;

    constructor(address _rollupProcessor, address _admin) BridgeBase(_rollupProcessor) {
        ADMIN = _admin;
    }

   /**
    @notice Function that adds an aggregation pool
    @dev Only an admin can add a pool, the admin must also withlist the pool on the alcheemist contract
    @param _yToken - The yield token that the pool will use 
    @param _underlyingToken - The underlying token that the pool will use to earn yield.
    @param _alchemist - The address of the alchemist to use.
    @param _alToken - The alToken that debt is taken out in
    @param _colRatio - The initial col ratio 
    @param _name - name of ERC20
    @param _symbol - symbol of ERC20
    @return - the address of the pool
    */ 
    function addPool(
        address _yToken, 
        address _underlyingToken, 
        address _alchemist,
        address _alToken,
        uint256 _colRatio, 
        string memory _name, 
        string memory _symbol
        ) external returns (address)
    {
        require(msg.sender == ADMIN);
        
        AlchemixPool alchemixPool = new AlchemixPool(
            address(this),
            _yToken,
            _underlyingToken,
            _alchemist,
            _alToken,
            _colRatio,
            _name,
            _symbol 
        );

        pools.push(address(alchemixPool));
        return address(alchemixPool);
    }

   /**
    @notice Function that adds an funding pool
    @dev Only an admin can add a pool, the admin must also withlist the pool on the alcheemist contract
    @param _yToken - The yield token that the pool will use 
    @param _underlyingToken - The underlying token that the pool will use to earn yield.
    @param _alchemist - The address of the alchemist to use
    @param _alToken - The alToken that debt is taken out in
    @param _beneficiary - The address of the beneficiary that will receive funds 
    @param _colRatio - The initial col ratio 
    @param _name - name of ERC20
    @param _symbol - symbol of ERC20
    @return - the address of the pool
    */ 
    function addFundingPool(
        address _yToken, 
        address _underlyingToken, 
        address _alchemist,
        address _alToken,
        address _beneficiary,
        uint256 _colRatio, 
        string memory _name, 
        string memory _symbol
        ) external returns (address)
    {
        require(msg.sender == ADMIN);
        
        AlchemixFundingPool alchemixFundingPool = new AlchemixFundingPool(
            address(this),
            _yToken,
            _underlyingToken,
            _alchemist,
            _alToken,
            _beneficiary,
            _colRatio,
            _name,
            _symbol 
        );

        pools.push(address(alchemixFundingPool));
        return address(alchemixFundingPool);
    }

    /**
      @notice Function that either deposits and mints or repays and withdraws
      @dev The flow of this functions is based on the type of input and output assets.
     
      @param _inputAssetA - Either the underlying token when depositing or shareToken when withdrawing 
      @param _inputAssetB - Allways empty 
      @param _outputAssetA - Underlying token when withdrawing alToken when depositing
      @param _outputAssetB - shareToken when depositing and empty when withdrawing
      @param _totalInputValue - amount of underlying tokens when depositing and share tokens when withdrawing 
      @param _interactionNonce - Globablly unique identifier for this bridge call
      @param _auxData - selects which pool to use
      @return outputValueA - Amount of shareTokens when depositing and underlying token when withdrawing

      @return outputValueB - Amount of debt taken out when minting and nothing when withdrawing
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
    ){
        isAsync = false;

        address pool = pools[_auxData];
        address underlyingToken =  AlchemixPool(pool).UNDERLYING_TOKEN(); 
        address alToken = AlchemixPool(pool).ALTOKEN(); 

        // Deposit and mint 
        if (_inputAssetA.erc20Address == underlyingToken && 
            _outputAssetB.erc20Address == pool
        ){
            if (_outputAssetA.erc20Address == alToken){
                IERC20(underlyingToken).transfer(pool, _totalInputValue);
                (outputValueA, outputValueB) = AlchemixPool(pool).depositAndMint(_totalInputValue);             
                IERC20(pool).approve(ROLLUP_PROCESSOR, outputValueA);
                IERC20(alToken).approve(ROLLUP_PROCESSOR, outputValueB);
            } 
            else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED ) {
                // FundingPool
                IERC20(underlyingToken).transfer(pool, _totalInputValue);
                outputValueA = AlchemixFundingPool(pool).depositAndMint(_totalInputValue);             
                IERC20(pool).approve(ROLLUP_PROCESSOR, outputValueA);

            } else revert ErrorLib.InvalidInput();
        }

        // Repay and withdraw. FundingPools and simple pools share the same input/output and ABI when withdrawing
        else if (_inputAssetA.erc20Address == pool &&
            _outputAssetA.erc20Address == underlyingToken 
        ){
            outputValueA = AlchemixPool(pool).repayAndWithdraw(_totalInputValue);             
            IERC20(underlyingToken).approve(ROLLUP_PROCESSOR, outputValueA);

        } else revert ErrorLib.InvalidInput();
    }
}
