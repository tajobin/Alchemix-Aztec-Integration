// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAlchemistV2} from "../../../interfaces/alchemix/IAlchemistV2.sol";
import {AlchemixBridge} from "../../../bridges/alchemix/AlchemixBridge.sol";

import "forge-std/console2.sol";

interface IWhitelist{
  function add(address caller) external;
}

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract AlchemistFundingUnitTest is BridgeTestBase {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant ALCHEMIST = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd; // Address of the alUSD Alchemist
    address private constant YVDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;  
    address private constant ALUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address private constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address private constant WHITELIST = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address private ALCHEMIX_POOL;

    address private constant GITCOIN_MATCHING_POOL =  0xde21F729137C5Af1b01d73aF1dC21eFfa2B8a0d6;

    AztecTypes.AztecAsset public daiAsset;
    AztecTypes.AztecAsset public poolAsset;
    AztecTypes.AztecAsset public alusdAsset;
    AztecTypes.AztecAsset public empty;

    address private rollupProcessor;
    AlchemixBridge internal bridge;

    uint256 private id;

    IERC20 dai;
    IAlchemistV2 alchemist; 

    function setUp() public {
        rollupProcessor = address(this);

        bridge = new AlchemixBridge(rollupProcessor, ADMIN);

        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "Alchemix Bridge");

        daiAsset  = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: DAI,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        alusdAsset = AztecTypes.AztecAsset({
            id: 3,
            erc20Address: ALUSD,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

    }

    function _addNewFundingDaiPool(uint256 _colRatio, address _beneficiary) internal returns (address pool){
        vm.startPrank(ADMIN);
        pool = bridge.addFundingPool(YVDAI, DAI, ALCHEMIST, ALUSD, _beneficiary, _colRatio, "","");
        IWhitelist(WHITELIST).add(pool);
        vm.stopPrank();
    }

    function testDepositAndMint() public {
        uint256 balanceBefore = IERC20(ALUSD).balanceOf(GITCOIN_MATCHING_POOL);
        uint256 colRatio = 3 ether;
        address pool = _addNewFundingDaiPool(colRatio, GITCOIN_MATCHING_POOL);

        poolAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: pool,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 depositAmount = 10 ether;
        deal(DAI, address(bridge), depositAmount);
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset, 
            emptyAsset, 
            emptyAsset, 
            poolAsset, 
            depositAmount, 
            1, 
            0, 
            address(0)
        );
        
        uint256 balanceAfter = IERC20(ALUSD).balanceOf(GITCOIN_MATCHING_POOL);
        IERC20(pool).transferFrom(address(bridge), address(this), outputValueA);

        assertEq(balanceAfter-balanceBefore, depositAmount*1e18/colRatio);
    }

    function testRepayAndWithdraw() public {
        uint256 balanceBefore = IERC20(ALUSD).balanceOf(GITCOIN_MATCHING_POOL);
        uint256 colRatio = 3 ether;
        address pool = _addNewFundingDaiPool(colRatio, GITCOIN_MATCHING_POOL);

        poolAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: pool,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 depositAmount = 10 ether;
        deal(DAI, address(bridge), depositAmount);
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset, 
            emptyAsset, 
            emptyAsset, 
            poolAsset, 
            depositAmount, 
            1, 
            0, 
            address(0)
        );
        
        uint256 balanceAfter = IERC20(ALUSD).balanceOf(GITCOIN_MATCHING_POOL);
        IERC20(pool).transferFrom(address(bridge), address(this), outputValueA);

        uint256 debtTakenOut = balanceAfter-balanceBefore;

        uint256 poolTokens = IERC20(pool).balanceOf(address(this));    

        IERC20(pool).transfer(address(bridge), poolTokens);
        (uint256 collateralWithdrawn, ,) = bridge.convert(
            poolAsset, 
            emptyAsset, 
            daiAsset, 
            emptyAsset, 
            poolTokens, 
            2, 
            0, 
            address(0)
        );

        uint256 expectedColBack = (depositAmount-debtTakenOut);
        assertGe(collateralWithdrawn, expectedColBack*0.99e18/1e18);
    }
}