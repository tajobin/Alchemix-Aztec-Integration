// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import { DefiBridgeProxy } from "./../../aztec/DefiBridgeProxy.sol";
import { RollupProcessor } from "./../../aztec/RollupProcessor.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IndexBridgeContract } from "./../../bridges/indexcoop/IndexBridge.sol";
import { AztecTypes } from "./../../aztec/AztecTypes.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { TickMath } from "../../bridges/uniswapv3/libraries/TickMath.sol";
import { FullMath } from "../../bridges/uniswapv3/libraries/FullMath.sol";
import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import {IUniswapV3Factory} from"@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IStethPriceFeed} from '../../bridges/indexcoop/interfaces/IStethPriceFeed.sol';
import {ISupplyCapIssuanceHook} from '../../bridges/indexcoop/interfaces/ISupplyCapIssuanceHook.sol';
import {IAaveLeverageModule} from '../../bridges/indexcoop/interfaces/IAaveLeverageModule.sol';
import {ICurvePool} from '../../bridges/indexcoop/interfaces/ICurvePool.sol';
import {IWeth} from '../../bridges/indexcoop/interfaces/IWeth.sol';
import {IExchangeIssue} from '../../bridges/indexcoop/interfaces/IExchangeIssue.sol';
import {ISetToken} from '../../bridges/indexcoop/interfaces/ISetToken.sol';
import {IStableSwapOracle} from '../../bridges/indexcoop/interfaces/IStableSwapOracle.sol';

import "../../../lib/forge-std/src/Test.sol";

contract IndexTest is Test {
    using SafeMath for uint256;
    using stdStorage for StdStorage;

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    IndexBridgeContract indexBridge;

    address ROLLUP_PROCESSOR;
    address immutable EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address immutable CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address immutable STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
    address immutable STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address immutable AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address immutable ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B; 
    address immutable STABLE_SWAP_ORACLE = 0x3A6Bd15abf19581e411621D669B6a2bbe741ffD6;

    address immutable UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address immutable UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address immutable UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; 

    AztecTypes.AztecAsset empty;
    AztecTypes.AztecAsset ethAztecAsset = AztecTypes.AztecAsset({
        id: 1,
        erc20Address: ETH ,
        assetType: AztecTypes.AztecAssetType.ETH
    });
    AztecTypes.AztecAsset icethAztecAssetA = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: address(ICETH),
        assetType: AztecTypes.AztecAssetType.ERC20
    });

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    receive() external payable {} 

    function setUp() public {
        _aztecPreSetup();
        indexBridge = new IndexBridgeContract(
            address(rollupProcessor)
        );
        ROLLUP_PROCESSOR = address(rollupProcessor);
    }

    function testIssueSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e8, 500 ether);

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        deal(address(rollupProcessor), inputValue);
        (uint256 newICETH, uint256 returnedEth, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                inputValue,
                1,
                auxData
        );
        
    }

    function testBuySet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1, 500 ether);
        
        uint256 inputValue = 200 ether;

        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        uint24 uniFee = 3000;
        bytes memory path = abi.encodePacked(WETH, uniFee);
        path = abi.encodePacked(path, ICETH);
        uint256 icethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, inputValue);
        uint256 minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), WETH, ICETH, uniFee).mul(maxSlipAux).div(1e4);

        if (icethFromQuoter < minimumReceivedDex){

            deal(address(indexBridge), inputValue);
            hoax(ROLLUP_PROCESSOR);
            vm.expectRevert(bytes("Too little received"));
            indexBridge.convert(
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                inputValue,
                1,
                auxData,
                address(0)
            );

        } else {

            deal(ROLLUP_PROCESSOR, inputValue);
            console2.log('Attempt Buy');
            (uint256 newICETH, ,) =
                rollupProcessor.convert(
                    address(indexBridge),
                    ethAztecAsset,
                    empty,
                    icethAztecAssetA,
                    ethAztecAsset,
                    inputValue,
                    1,
                    auxData
            );
            assertGe(newICETH, minimumReceivedDex, "A smaller amount than expected was returned when buying icETH from univ3");
        }
    }

    function testRedeemSet(uint256 inputValue) public{
        inputValue = bound(inputValue, 1e8, 500 ether);

        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 flowSelector = 1;
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);
        uint256 minimumReceivedRedeem = getMinEth(inputValue, maxSlipAux);

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;
        hoax(hoaxAddress, 20);

        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);
        (uint256 newEth, , ) =
             rollupProcessor.convert(
                address(indexBridge),
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                inputValue,
                2,
                auxData
        );

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 
        assertTrue(safe, "Swapped on Curve stETH pool with unsafe Lido Oracle");
        assertGe(newEth, minimumReceivedRedeem, "Received to little ETH from redeem");
   } 

    function testSellSet(uint256 inputValue) public{
        inputValue = bound(inputValue, 1, 500 ether);
        
        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;

        uint256 ethFromQuoter; uint256 minimumReceivedDex;
        {
            uint24 uniFee = 3000;
            bytes memory path = abi.encodePacked(ICETH, uniFee);
            path = abi.encodePacked(path, WETH);
            ethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, inputValue);
            minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), ICETH, WETH, uniFee).
                mul(maxSlipAux).
                div(1e4)
            ;
        }

        if (ethFromQuoter < minimumReceivedDex){ //If price impact is to large revert when swapping
            console2.log('Expect Revert');
            hoax(hoaxAddress, 20);
            IERC20(ICETH).transfer(address(indexBridge), inputValue);
            hoax(ROLLUP_PROCESSOR);
            vm.expectRevert(bytes('Too little received'));
            indexBridge.convert(
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                inputValue,
                2,
                auxData,
                address(0)
            );

        } else { //If price impact is not to large swap and receive more or equal to the minimum

            console2.log('Selling');
            hoax(hoaxAddress, 20);
            IERC20(ICETH).transfer(address(rollupProcessor), inputValue);

            (uint256 newEth, ,) =
                rollupProcessor.convert(
                    address(indexBridge),
                    icethAztecAssetA,
                    empty,
                    ethAztecAsset,
                    empty,
                    inputValue,
                    2,
                    auxData
            );
            assertGe(newEth, minimumReceivedDex, "Received to little ETH from dex");
        }
   } 

    function testIncorrectFlowSelector() public {
        uint256 inputValue = 5 ether;
        uint64 flowSelector = 10;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        startHoax(ROLLUP_PROCESSOR);
        vm.expectRevert(IndexBridgeContract.IncorrectFlowSelector.selector);

        // Test on redeem/sell flow
        indexBridge.convert(
            icethAztecAssetA,
            empty,
            ethAztecAsset,
            empty,
            inputValue,
            2,
            auxData,
            address(0)
        );

        // Test on redeem/sell flow
        vm.expectRevert(IndexBridgeContract.IncorrectFlowSelector.selector);
        indexBridge.convert(
            ethAztecAsset,
            empty,
            icethAztecAssetA,
            ethAztecAsset,
            inputValue,
            1,
            auxData,
            address(0)
        );
    }

    function testIncorrectInput() public {

        vm.prank(ROLLUP_PROCESSOR);
        vm.expectRevert(IndexBridgeContract.IncorrectInput.selector);
        indexBridge.convert(
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            0,
            0,
            0,
            address(0)
        );
    }

    function testUnsafeLidoOracle(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e8, 500 ether);

        // Make Lido's Oracle unsafe
        stdstore
            .target(STABLE_SWAP_ORACLE)
            .sig(IStableSwapOracle.stethPrice.selector)
            .checked_write(7777)
        ;

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        startHoax(ROLLUP_PROCESSOR);
        vm.expectRevert(IndexBridgeContract.UnsafeStableSwapOracle.selector);

        // Test on redeem 
        indexBridge.convert(
            icethAztecAssetA,
            empty,
            ethAztecAsset,
            empty,
            inputValue,
            2,
            auxData,
            address(0)
        );

        // Test on buy 
        vm.expectRevert(IndexBridgeContract.UnsafeStableSwapOracle.selector);
        indexBridge.convert(
            ethAztecAsset,
            empty,
            icethAztecAssetA,
            ethAztecAsset,
            inputValue,
            1,
            auxData,
            address(0)
        );
    }

    function testToSmallInput(uint256 inputValue) public {
        vm.assume(inputValue < 1e8);
        vm.assume(inputValue > 1);

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        startHoax(ROLLUP_PROCESSOR);
        vm.expectRevert(IndexBridgeContract.InputToSmall.selector);

        // Test on redeem 
        indexBridge.convert(
            icethAztecAssetA,
            empty,
            ethAztecAsset,
            empty,
            inputValue,
            2,
            auxData,
            address(0)
        );

        // Test on buy 
        vm.expectRevert(IndexBridgeContract.InputToSmall.selector);
        indexBridge.convert(
            ethAztecAsset,
            empty,
            icethAztecAssetA,
            ethAztecAsset,
            inputValue,
            1,
            auxData,
            address(0)
        );
    }
    
    function encodeAuxdata(uint64 a, uint64 b) internal view returns(uint64 encoded) {
        encoded |= (b << 32);
        encoded |= (a);
        return encoded;
    }

    function decodeAuxdata(uint64 encoded) internal view returns (uint64 a, uint64 b) {
        b = encoded >> 32;
        a = (encoded << 32) >> 32;
    }

    function getMinEth(uint256 setAmount, uint256 maxSlipAux) internal returns (uint256) {

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 

        IExchangeIssue.LeveragedTokenData memory issueInfo = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH), 
            setAmount, 
            true
        );        

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = issueInfo.collateralAmount.mul(price).div(1e18); 

        return (colInEth - issueInfo.debtAmount).mul(maxSlipAux).div(1e14);
    }

    function getMinIceth(
        uint256 totalInputValue, 
        uint64 maxSlipAux
        )
        internal 
        returns (uint256 minIcToReceive)
    {
        
        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 

        IExchangeIssue.LeveragedTokenData memory data = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH),
            1e18,
            true
        );

        uint256 costOfOneIc = (data.collateralAmount.
            mul(1.0009 ether).
            div(1e18).
            mul(price).
            div(1e18) 
            )
            - data.debtAmount
        ;

        minIcToReceive = totalInputValue.mul(maxSlipAux).mul(1e12).div(costOfOneIc);
    }

    function getAmountBasedOnTwap(
        uint128 amountIn, 
        address baseToken, 
        address quoteToken, 
        uint24 uniFee
        ) 
        internal 
        returns (uint256 amountOut)
    { 
        address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            WETH,
            ICETH,
            uniFee
        );

        uint32 secondsAgo = 60*10; 

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 arithmeticmeanTick = int24(tickCumulativesDelta / int32(secondsAgo)); 
        
        if (
            tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0) 
        ) {
            arithmeticmeanTick--;
        }

        amountOut = getQuoteAtTick(
            arithmeticmeanTick,
            amountIn,
            baseToken,
            quoteToken
        );
    }

    function getQuoteAtTick(
            int24 tick, 
            uint128 baseAmount,
            address baseToken,
            address quoteToken
        ) internal pure returns (uint256 quoteAmount) {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                    : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
                quoteAmount = baseToken < quoteToken
                    ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                    : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
            }
    }
}
