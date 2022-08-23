// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAlchemistV2} from "../../../interfaces/alchemix/IAlchemistV2.sol";

import "forge-std/console2.sol";

interface IWhitelist{
  function add(address caller) external;
}


// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract AlchemistBasicTest is Test {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDALCH = 0x5C6374a2ac4EBC38DeA0Fc1F8716e5Ea1AdD94dd; // Address of the alUSD Alchemist
    address private constant YVDAI = 0xdA816459F1AB5631232FE5e97a05BBBb94970c95;  
    address private constant ALUSD = 0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9;
    address private constant ADMIN = 0x9e2b6378ee8ad2A4A95Fe481d63CAba8FB0EBBF9;
    address private constant WHITELIST = 0x78537a6CeBa16f412E123a90472C6E0e9A8F1132;
 

    IERC20 dai;
    IAlchemistV2 alchemist; 
    function setUp() public {
        alchemist = IAlchemistV2(USDALCH);
        dai = IERC20(DAI);



    }

    function testDeposit() public {
        /**
            1. Get some dai
            2. Use depositUnderlying() 
            3. Check shares?
         */

       // lets hoax to pretend to be an actual address to pass whitlist 
        address hoaxAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.startPrank(hoaxAddress, hoaxAddress);

        dai.approve(USDALCH, 10 ether);
        uint256 ret = alchemist.depositUnderlying(YVDAI, 10 ether, hoaxAddress, 5);


        console2.log('ret', ret);

        uint256 reret = alchemist.getUnderlyingTokensPerShare(YVDAI);

        console2.log('reret', reret*ret/1e18);

    }

    /**
    
    function testMint() public {
        uint256 amount = 10 ether;
        address hoaxaddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.startprank(hoaxaddress, hoaxaddress);
        dai.approve(USDALCH, amount);
        uint256 ret = alchemist.depositunderlying(YVDAI, amount, hoaxaddress, 5);

        alchemist.mint(3 ether, hoaxaddress);

        uint256 alusd = IERC20(0xbc6da0fe9ad5f3b0d58160288917aa56653660e9).balanceof(hoaxaddress);
        console2.log('alusd', alusd);

    }
    
     */

    function testRepayAndWithdraw() public {
    
        uint256 amount = 10 ether;
        address hoaxAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.startPrank(hoaxAddress, hoaxAddress);
        dai.approve(USDALCH, 100 ether);
        uint256 ret = alchemist.depositUnderlying(YVDAI, amount, hoaxAddress, 5);
        alchemist.mint(3 ether, hoaxAddress);
        uint256 alUSD = IERC20(ALUSD).balanceOf(hoaxAddress);

        console2.log('alUSD', alUSD);

        //Start withdraw process

        // Pay back all of the debt
        IERC20(DAI).approve(USDALCH, alUSD);
        uint256 received = alchemist.repay(DAI, alUSD/2, hoaxAddress);
        console2.log('received', received);

        // now withdraw 
         alchemist.withdrawUnderlying(YVDAI, ret/2, hoaxAddress, ret/3);

    }

    function testLiquiWithdraw() public {
        address hoaxAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        uint256 balanceBefore = dai.balanceOf(hoaxAddress);
        uint256 amount = 10 ether;
        vm.startPrank(hoaxAddress, hoaxAddress);
        dai.approve(USDALCH, 10 ether);
        uint256 ret = alchemist.depositUnderlying(YVDAI, amount, hoaxAddress, 5);
        alchemist.mint(3 ether, hoaxAddress);
        uint256 alUSD = IERC20(ALUSD).balanceOf(hoaxAddress);

        uint256 sharesLiduidated = alchemist.liquidate(YVDAI, ret, 1);

        uint256 balanceAfter = dai.balanceOf(hoaxAddress);

        console2.log("dai lost", (balanceBefore-balanceAfter)/1e16);
    }

    function testColCalc() public {
        uint256 amount = 10 ether;
        address hoaxAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.startPrank(hoaxAddress, hoaxAddress);
        dai.approve(USDALCH, amount);
        uint256 ret = alchemist.depositUnderlying(YVDAI, amount, hoaxAddress, 5);

        alchemist.mint(3 ether, hoaxAddress);

        uint256 alUSD = IERC20(0xBC6DA0FE9aD5f3b0d58160288917AA56653660E9).balanceOf(hoaxAddress);

        alchemist.poke(hoaxAddress);

        uint256 tokenPerShare = alchemist.getUnderlyingTokensPerShare(YVDAI);

        (int256 debt, ) = alchemist.accounts(hoaxAddress); // @note correct way to get debt after poke?
        (uint256 shares, ) = alchemist.positions(hoaxAddress, YVDAI); // @note same for shares 

        uint256 tokenAmount = tokenPerShare*shares/1e18;
        uint256 collate = tokenAmount*1e18/uint256(debt); 

        console2.log("col", collate);
    }

    function testWhiteListAccess() public {
        vm.prank(ADMIN);
        IWhitelist(WHITELIST).add(address(this));

        uint256 amount = 10 ether;
        deal(DAI, address(this), amount);
        dai.approve(USDALCH, 10 ether);
        uint256 ret = alchemist.depositUnderlying(YVDAI, 10 ether, address(this), 5);
        uint256 reret = alchemist.getUnderlyingTokensPerShare(YVDAI);

        console2.log('reret', reret*ret/1e18);

    }





}