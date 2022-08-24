// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAlchemistV2} from "../../../interfaces/alchemix/IAlchemistV2.sol";
import {AlchemixBridge} from "../../../bridges/alchemix/AlchemixBridge.sol";
import {AlchemixPool} from "../../../bridges/alchemix/AlchemixPool.sol";


interface IWhitelist{
  function add(address caller) external;
}

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract AlchemistUnitTest is BridgeTestBase {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant ALCHEMIST = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd; // Address of the alUSD Alchemist
    address private constant YVDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;  
    address private constant ALUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address private constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address private constant WHITELIST = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
    address private ALCHEMIX_POOL;

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

    function _addNewDaiPool(uint256 _colRatio) internal returns (address pool){
        vm.startPrank(ADMIN);
        pool = bridge.addPool(YVDAI, DAI, ALCHEMIST, ALUSD, _colRatio, "","");
        IWhitelist(WHITELIST).add(pool);
        vm.stopPrank();
    }

    function testDepositAndMint() public {
        uint256 colRatio = 3 ether;
        uint256 depositAmount = 10 ether;
        address pool = _addNewDaiPool(colRatio);

        uint256 expectedAlUsd = depositAmount*1e18/colRatio;
        address alchemistAddress  = AlchemixPool(pool).ALCHEMIST();

        uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YVDAI);
        uint256 expectedShares = depositAmount*1e18/tokenPerShare;

        (uint256 alUsdReturned, uint256 sharesReturned) = _depositAndMint(depositAmount, pool, 1);

        assertEq(alUsdReturned, expectedAlUsd);
        assertGe(sharesReturned, expectedShares*0.98e18/1e18); // Taking potential slippage into account
    }

    function testFuzzingDepositAndMint(uint256 depositAmount, uint256 colRatio) public {
        //uint256 colRatio = 3 ether;
        //uint256 depositAmount = 10 ether;
        depositAmount = bound(depositAmount, 1e18, 100e18);
        colRatio = bound(colRatio, 2e18, 10e18);

        address pool = _addNewDaiPool(colRatio);

        uint256 expectedAlUsd = depositAmount*1e18/colRatio;
        address alchemistAddress  = AlchemixPool(pool).ALCHEMIST();

        uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YVDAI);
        uint256 expectedShares = depositAmount*1e18/tokenPerShare;

        (uint256 alUsdReturned, uint256 sharesReturned) = _depositAndMint(depositAmount, pool, 1);

        assertEq(alUsdReturned, expectedAlUsd);
        assertGe(sharesReturned, expectedShares*0.98e18/1e18); // Taking potential slippage into account
    }

    function testRepayAndWithdraw() public {
        uint256 colRatio = 2 ether;
        uint256 depositAmount = 2 ether;
        address pool = _addNewDaiPool(colRatio);

        (uint256 debtTakenOut, uint256 shareTokens) = _depositAndMint(depositAmount, pool, 1);
        uint256 collateralWithdrawn = _repayAndWithdraw(shareTokens, pool, 2);

        uint256 expectedColBack = (depositAmount-debtTakenOut);

        assertGe(collateralWithdrawn, expectedColBack*0.99e18/1e18);
    }

    function testFuzzingRepayAndWithdraw(uint256 depositAmount, uint256 colRatio) public {
        //uint256 colRatio = 3 ether;
        //uint256 depositAmount = 10 ether;

        depositAmount = bound(depositAmount, 1e18, 100e18);
        colRatio = bound(colRatio, 2e18, 10e18);

        address pool = _addNewDaiPool(colRatio);

        (uint256 debtTakenOut, uint256 shareTokens) = _depositAndMint(depositAmount, pool, 1);
        uint256 collateralWithdrawn = _repayAndWithdraw(shareTokens, pool, 2);

        uint256 expectedColBack = (depositAmount-debtTakenOut);
        assertGe(collateralWithdrawn, expectedColBack*0.99e18/1e18);
    }

    function testFuzzingMultiDeposit(
            uint256 colRatio, 
            uint256 depositFirstCohort, 
            uint256 depositSecondCohort
            ) public 
        {
        
        colRatio = bound(colRatio, 2e18, 10e18);
        depositFirstCohort = bound(depositFirstCohort, 1e18, 100e18);
        depositSecondCohort = bound(depositSecondCohort, 1e18, 100e18);

        address pool = _addNewDaiPool(colRatio);

        (uint256 debtFirstCohort, uint256 sharesFirstCohort) = _depositAndMint(depositFirstCohort, pool, 1);
        (uint256 debtSecondCohort, uint256 sharesSecondCohort) = _depositAndMint(depositSecondCohort, pool, 2);

        uint256 firstCohortWithdraw = _repayAndWithdraw(sharesFirstCohort, pool, 3);
        uint256 expectedFirstCohortWithdraw = (depositFirstCohort-debtFirstCohort);
        assertGe(firstCohortWithdraw, expectedFirstCohortWithdraw*0.99e18/1e18);

        uint256 secondCohortWithdraw = _repayAndWithdraw(sharesSecondCohort, pool, 3);
        uint256 expectedSecondCohortWithdraw = (depositSecondCohort-debtSecondCohort);
        assertGe(secondCohortWithdraw, expectedSecondCohortWithdraw*0.99e18/1e18);
    }

    struct YieldGained {
        uint256 PhaseOne; 
        uint256 PhaseTwo; 
        uint256 PhaseThree; 
    }

    function testMultiDepositWithSimulatedYield() public {
        uint256 colRatio = 5 ether;

        YieldGained memory yieldGained = YieldGained(0.01e18, 0.02e18, 0.05e18);
        uint256 depositFirstCohort = 2 ether;

        address pool = _addNewDaiPool(colRatio);

        (uint256 debtFirstCohort, uint256 sharesFirstCohort) = _depositAndMint(depositFirstCohort, pool, 1);

        // Simulate x days has passed and yiledGainedInPercent in yield has been gained when cohort two enters
        _simulateYield(yieldGained.PhaseOne, pool);

        uint256 depositSecondCohort = 4 ether; 
        (uint256 debtSecondCohort, uint256 sharesSecondCohort) = _depositAndMint(depositSecondCohort, pool, 2);

        // Simulate y days passes and yieldGainedPhaseTwo in yield has been gained.
        _simulateYield(yieldGained.PhaseTwo, pool); 

        // 10% of cohort 1 now exits
        uint256 colOutCohortOne = _repayAndWithdraw(sharesFirstCohort/10, pool, 3);

        // Total yield during phase 1 and hase 2 =
        uint256 expectedColOutCohortOne = 
            (depositFirstCohort/10)*
            (1e18 + yieldGained.PhaseOne + yieldGained.PhaseTwo)/1e18 - debtFirstCohort/10;


        assertGe(colOutCohortOne, expectedColOutCohortOne*0.999e18/1e18);
    
        // Simulate z days passes and yieldGainedPhaseThree in yield has been gained.

        _simulateYield(yieldGained.PhaseThree, pool); 
        
        // 20% of cohort 2 now exits
        uint256 colOutCohortTwo = _repayAndWithdraw(sharesSecondCohort/20, pool, 4);

        uint256 expectedColOutCohortTwo = 
            (depositSecondCohort/20)*
            (1e18 + yieldGained.PhaseTwo + yieldGained.PhaseThree)/1e18 - debtSecondCohort/20;


        assertGe(colOutCohortTwo, expectedColOutCohortTwo*0.999e18/1e18);
    }

    function testFuzzingMultiDepositWithSimulatedYield(
        uint256 colRatio, 
        uint256 depositFirstCohort,
        uint256 depositSecondCohort
        ) 
        public 
    {
        colRatio = bound(colRatio, 2e18, 5e18);
        depositFirstCohort = bound(depositFirstCohort, 1e18, 100e18);
        depositSecondCohort = bound(depositSecondCohort, 1e18, 100e18);

        YieldGained memory yieldGained = YieldGained(0.01e18, 0.02e18, 0.025e18);

        address pool = _addNewDaiPool(colRatio);

        (uint256 debtFirstCohort, uint256 sharesFirstCohort) = _depositAndMint(depositFirstCohort, pool, 1);

        // Simulate x days has passed and yiledGainedInPercent in yield has been gained when cohort two enters
        _simulateYield(yieldGained.PhaseOne, pool);
        
        (uint256 debtSecondCohort, uint256 sharesSecondCohort) = _depositAndMint(depositSecondCohort, pool, 2);

        // Simulate y days passes and yieldGainedPhaseTwo in yield has been gained.
        _simulateYield(yieldGained.PhaseTwo, pool); 

        // 10% of cohort 1 now exits
        uint256 colOutCohortOne = _repayAndWithdraw(sharesFirstCohort/10, pool, 3);

        // Total yield during phase 1 and hase 2 =
        uint256 expectedColOutCohortOne = 
            (depositFirstCohort/10)*
            (1e18 + yieldGained.PhaseOne + yieldGained.PhaseTwo)/1e18 - debtFirstCohort/10;


        assertGe(colOutCohortOne, expectedColOutCohortOne*0.999e18/1e18);
    
        // Simulate z days passes and yieldGainedPhaseThree in yield has been gained.

        _simulateYield(yieldGained.PhaseThree, pool); 

        // 20% of cohort 2 now exits
        uint256 colOutCohortTwo = _repayAndWithdraw(sharesSecondCohort/20, pool, 4);

        uint256 expectedColOutCohortTwo = 
            (depositSecondCohort/20)*
            (1e18 + yieldGained.PhaseTwo + yieldGained.PhaseThree)/1e18 - debtSecondCohort/20;

        assertGe(colOutCohortTwo, expectedColOutCohortTwo*0.999e18/1e18);
    }
   
    function _repayAndWithdraw(
        uint256 _shareTokens, 
        address pool, 
        uint256 _id
        ) 
        internal  
        returns (uint256 collateralWithdrawn)
    {
        IERC20(pool).transfer(address(bridge), _shareTokens);
        (collateralWithdrawn, ,) = bridge.convert(
            poolAsset, 
            emptyAsset, 
            daiAsset, 
            emptyAsset, 
            _shareTokens, 
            _id, 
            0, 
            address(0)
        );

        IERC20(DAI).transferFrom(address(bridge),address(this), collateralWithdrawn);
    }

    function _depositAndMint(
        uint256 _depositAmount, 
        address _pool, 
        uint256 _id
        )
        internal 
        returns (uint256 debtTakenOut, uint256 shareTokens)
    {

        poolAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: _pool,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(DAI, address(bridge), _depositAmount);
        (shareTokens, debtTakenOut, ) = bridge.convert(
            daiAsset, 
            emptyAsset, 
            alusdAsset, 
            poolAsset, 
            _depositAmount, 
            _id, 
            0, 
            address(0)
        );

        IERC20(ALUSD).transferFrom(address(bridge), address(this), debtTakenOut);
        IERC20(_pool).transferFrom(address(bridge), address(this), shareTokens);
    }

    // Simulate yield gained by paying off debt 
    function _simulateYield(uint256 yieldGainedInPercent, address _pool) internal returns (uint256 amountRepaied){

        uint256 totalShares = IERC20(_pool).totalSupply();
        uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YVDAI);
        uint256 totalUnderlying = totalShares*tokenPerShare/1e18;
        uint256 yieldInUnderlying = yieldGainedInPercent*totalUnderlying/1e18;

        address alchemistAddress  = AlchemixPool(_pool).ALCHEMIST();

        deal(DAI, _pool, yieldInUnderlying);
        vm.startPrank(_pool); //pretend to be pool to pass whitelist check
        IERC20(DAI).approve(alchemistAddress, yieldInUnderlying);
        uint256 amountRepaied  = IAlchemistV2(alchemistAddress).repay(DAI, yieldInUnderlying, _pool);
        vm.stopPrank();
    }

    function testSimulatedYield () public {
        uint256 colRatio = 3 ether;
        uint256 depositAmount = 10 ether;
        address pool = _addNewDaiPool(colRatio);

        uint256 expectedAlUsd = depositAmount*1e18/colRatio;
        address alchemistAddress  = AlchemixPool(pool).ALCHEMIST();
        (uint256 alUsdReturned, uint256 sharesReturned) = _depositAndMint(depositAmount, pool, 1);

        vm.startPrank(pool); //pretend to be pool to pass whitelist check
        (uint256 colBefore, int256 debt, uint256 shares, uint256 tokensPerShare) = _getPoolInfo(pool);
        vm.stopPrank();

        uint256 collateralInUnderlying = shares*tokensPerShare/1e18;
        uint256 yieldGainedInPercent = 0.1e18;
        
        uint256 yieldInUnderlying = yieldGainedInPercent*collateralInUnderlying/1e18;
        uint256 expectedCol = collateralInUnderlying*1e18/(uint256(debt)-yieldInUnderlying);

        // Simulate yield
        _simulateYield(yieldGainedInPercent, pool);

        // calculate new col ratio and check that it should be what you expect.
        vm.startPrank(pool); //pretend to be pool to pass whitelist check
        (uint256 col, , , ) = _getPoolInfo(pool);
        vm.stopPrank();

        assertEq(col, expectedCol);
    }

    function _getPoolInfo(address _pool) internal returns (uint256 col, int256 debt, uint256 shares, uint256 tokenPerShare){
        address alchemistAddress  = AlchemixPool(_pool).ALCHEMIST();
        IAlchemistV2(ALCHEMIST).poke(_pool);
        
        tokenPerShare = IAlchemistV2(alchemistAddress).getUnderlyingTokensPerShare(YVDAI);
        (debt, ) = IAlchemistV2(alchemistAddress).accounts(_pool); 
        (shares, ) = IAlchemistV2(alchemistAddress).positions(_pool, YVDAI);

        uint256 tokenAmount = tokenPerShare*shares/1e18; 
        col = tokenAmount*1e18/uint256(debt); 
    }























    function testRevertInvalidInputDeposit() public {
        uint256 colRatio = 3 ether;
        uint256 depositAmount = 10 ether;
        address pool = _addNewDaiPool(colRatio);

        uint256 expectedAlUsd = depositAmount*1e18/colRatio;
        address alchemistAddress  = AlchemixPool(pool).ALCHEMIST();

        uint256 tokenPerShare = IAlchemistV2(ALCHEMIST).getUnderlyingTokensPerShare(YVDAI);
        uint256 expectedShares = depositAmount*1e18/tokenPerShare;

        poolAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: pool,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(DAI, address(bridge), depositAmount);

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert(
            daiAsset, 
            emptyAsset, 
            alusdAsset, 
            emptyAsset, 
            depositAmount, 
            1, 
            0, 
            address(0)
        );
    }

    function testRevertInvalidInputWithdraw() public {
        uint256 colRatio = 3 ether;
        address pool = _addNewDaiPool(colRatio);

        poolAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: pool,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 depositAmount = 10 ether;
        deal(DAI, address(bridge), depositAmount);
        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert(
            daiAsset, 
            emptyAsset, 
            alusdAsset, 
            poolAsset, 
            depositAmount, 
            1, 
            0, 
            address(0)
        );

        IERC20(ALUSD).transferFrom(address(bridge), address(this), outputValueB);
        IERC20(pool).transferFrom(address(bridge), address(this), outputValueA);

        uint256 debtTakenOut = IERC20(ALUSD).balanceOf(address(this));
        uint256 poolTokens = IERC20(pool).balanceOf(address(this));    

        IERC20(pool).transfer(address(bridge), poolTokens);

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        (uint256 outputValueAWithdraw, ,) = bridge.convert(
            poolAsset, 
            emptyAsset, 
            emptyAsset, 
            emptyAsset, 
            poolTokens, 
            2, 
            0, 
            address(0)
        );
    }
}