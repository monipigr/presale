// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Presale} from "../src/Presale.sol";
import {FlyToken} from "../src/FlyToken.sol";
import {MockTreasury} from "../src/MockTreasury.sol";
import {MockAggregator} from "../src/MockAggregator.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PresaleTest is Test {
    Presale public presale;
    FlyToken public flyToken;
    MockTreasury public mockTreasury;
    MockAggregator public mockAggregator;

    address public owner = address(this); 
    address public user = vm.addr(5);
    address public user2 = vm.addr(6);
    address userWithUsdt = vm.addr(7);

    address _usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address _usdcAddress =  vm.addr(3); 
    address _dataFeedAddress =  0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; 
    uint256 _maxSupply = 30000000 * 1e18; // 30M
    uint256 _startingTime = block.timestamp; 
    uint256 _endingTime = block.timestamp + 5000; 
    uint256[][3] _phases; 

    function setUp() public {
        _phases[0] = [10000000 * 1e18, 5000, block.timestamp + 1000];
        _phases[1] = [10000000 * 1e18, 500, block.timestamp + 1000]; 
        _phases[2] = [10000000 * 1e18, 50, block.timestamp + 1000];

        mockTreasury = new MockTreasury();
        mockAggregator = new MockAggregator(2000e8);
        flyToken = new FlyToken();
        flyToken.approve(address(this), 30_000_000 * 1e18);
        presale = new Presale(address(flyToken), _usdcAddress,  _usdtAddress, address(mockTreasury), address(mockAggregator), _phases,_maxSupply, _startingTime, _endingTime );

        deal(_usdtAddress, userWithUsdt, 100_000_000e6); // 100M USDT
    }

    receive() external payable {}

     /**
     * @notice Tests that the owner can successfully add a user to the blacklist.
     * @dev Uses `vm.prank` to impersonate the owner and verifies that the mapping updates correctly.
     */
    function test_blacklist() public {
        vm.startPrank(owner);
        presale.blacklist(user);    
        assertTrue(presale.isBlacklisted(user));
        vm.stopPrank();
    }

    /**
     * @notice Tests that non-owners cannot call `blacklist`.
     * @dev Expects a revert when a non-owner attempts to add a user to the blacklist.
     */
    function test_blacklist_revertsNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        presale.blacklist(user);
        vm.stopPrank();
    }

    /**
     * @notice Tests that the owner can remove a user from the blacklist.
     */
    function test_unblacklist() public {
        vm.startPrank(owner);
        presale.blacklist(user);
        presale.unBlacklist(user);
        assertFalse(presale.isBlacklisted(user));
        vm.stopPrank();
    }

    /**
     * @notice Tests that non-owners cannot call `unBlacklist`.
     * @dev Expects a revert when a non-owner attempts to remove a user from the blacklist.
     */
    function test_unblacklist_revertsNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        presale.unBlacklist(user2);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user can buy with USDT and the fee mechanism works correctly.
     * @dev 
     * - Approves Presale to spend user's USDT.
     * - Executes a buy with 1000 USDT.
     * - Verifies that:
     *    1. Funds receiver gets the net amount after fee.
     *    2. Fees are correctly accounted for in the contract.
     *    3. User's internal FlyToken balance increases.
     */
    function test_buyWithTokens() public {
        vm.startPrank(userWithUsdt);
        uint256 amountIn = 10e6; // 1000 USDT (6 decimales)

        IERC20(_usdtAddress).approve(address(presale), amountIn);

        uint256 beforeFundsReceiver = IERC20(_usdtAddress).balanceOf(address(mockTreasury));
        uint256 beforeFees = presale.collectedFees(_usdtAddress); 
        uint256 beforeUserDeposit = presale.userTokensDeposited(userWithUsdt);

        presale.buyWithTokens(_usdtAddress, amountIn);

        uint256 expectedFee = (amountIn * presale.FEE_BPS()) / 10_000; // fee en USDT
        uint256 expectedNet = amountIn - expectedFee;     

        uint256 afterFundsReceiver  = IERC20(_usdtAddress).balanceOf(address(mockTreasury));
        uint256 afterFees = presale.collectedFees(_usdtAddress);
        uint256 afterUserDeposit = presale.userTokensDeposited(userWithUsdt);

        assertEq(afterFundsReceiver - beforeFundsReceiver, expectedNet, "wrong net");
        assertEq(afterFees - beforeFees, expectedFee, "wrong fee");
        assertGt(afterUserDeposit - beforeUserDeposit, 0, "no tokens");

        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot buy with a token that is not accepted.
     */
    function test_buyWithTokens_revertsIfNotValidToken() public {
        vm.startPrank(user);
        address anotherTokenAddress = vm.addr(6);
        vm.expectRevert(bytes("Not Accepted Token"));
        presale.buyWithTokens(anotherTokenAddress, 1000e6);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot buy with 0 tokens.
     */
    function test_buyWithTokens_revertsIfNotEnoughTokens() public {
        vm.startPrank(user);
        IERC20(_usdtAddress).approve(address(presale), 0);
        vm.expectRevert(bytes("Zero amount"));
        presale.buyWithTokens(_usdtAddress, 0);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a blacklisted user cannot buy with tokens.
     */
    function test_buyWithTokens_revertsIfBlacklistedUser() public {
        vm.startPrank(owner);
        presale.blacklist(userWithUsdt);
        vm.stopPrank();

        vm.startPrank(userWithUsdt);
        vm.expectRevert(bytes("User is blacklisted"));
        presale.buyWithTokens(_usdtAddress, 1000e6);
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot buy with tokens if the presale has not started yet.
     */
    function test_buyWithTokens_revertsIfPresaleInactive() public {
        vm.startPrank(userWithUsdt);
        vm.warp(_startingTime -  1 days);
        vm.expectRevert(bytes("Presale inactive"));
        presale.buyWithTokens(_usdtAddress, 1000e6);
        vm.stopPrank();
    }

    /**
     * @notice Tests that buying more than maxSupply reverts.
     */
    function test_buyWithTokens_revertsIfMaxSupplyExceeded() public {
        vm.startPrank(userWithUsdt);
        uint256 hugeAmount = _maxSupply + 1e6;
        IERC20(_usdtAddress).approve(address(presale), hugeAmount);

        vm.expectRevert();
        presale.buyWithTokens(_usdtAddress, hugeAmount);

        vm.stopPrank();
    }

    /**
     * @notice Tests that the phase changes after reaching the phase 0 supply limit.
     * @dev Calculates the exact USDT amount needed to exhaust phase 0 supply,
     *      approves it, performs the buy, and checks that the phase advances.
     */
    function test_buyWithTokens_triggersPhaseChange() public {
        vm.startPrank(userWithUsdt);

        uint256 phase0Supply = presale.phases(0, 0); 
        uint256 phase0Price  = presale.phases(0, 1); 

        uint256 usdtNeeded = (phase0Supply * phase0Price) / 1e6;

        deal(_usdtAddress, userWithUsdt, usdtNeeded);

        IERC20(_usdtAddress).approve(address(presale), usdtNeeded);
        presale.buyWithTokens(_usdtAddress, usdtNeeded);

        assertEq(presale.currentPhase(), 1, "Phase did not change");

        vm.stopPrank();
    }


    /**
     * @notice Fuzz test for buyWithTokens with arbitrary USDT amounts.
     * @param amount Random USDT amount fuzzed by Foundry.
     */
    function testFuzz_buyWithTokens(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10_000e6);

        vm.startPrank(userWithUsdt);
        IERC20(_usdtAddress).approve(address(presale), amount);

        uint256 beforeBalance = presale.userTokensDeposited(userWithUsdt);

        presale.buyWithTokens(_usdtAddress, amount);

        uint256 afterBalance = presale.userTokensDeposited(userWithUsdt);

        assertGt(afterBalance - beforeBalance, 0, "User did not get tokens");
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user can buy with ETH and the fee mechanism works correctly.
     * @dev 
     * - Sends 1 ETH to buyWithETH.
     * - Verifies that:
     *    1. Funds receiver gets the net ETH after fee.
     *    2. ETH fees are correctly accounted for in the contract.
     *    3. User's internal FlyToken balance increases.
     */
    function test_buyWithETH() public {
        vm.startPrank(user);

        vm.deal(user, 1 ether);

        uint256 beforeFundsReceiver = address(mockTreasury).balance;
        uint256 beforeFees = presale.collectedETHFees();
        uint256 beforeUserDeposit = presale.userTokensDeposited(user);

        presale.buyWithETH{value: 1 ether}();

        uint256 expectedFee = (1 ether * presale.FEE_BPS()) / 10_000; 
        uint256 expectedNet = 1 ether - expectedFee;

        uint256 afterFundsReceiver = address(mockTreasury).balance;
        uint256 afterFees = presale.collectedETHFees();
        uint256 afterUserDeposit = presale.userTokensDeposited(user);

        assertEq(afterFundsReceiver - beforeFundsReceiver, expectedNet, "wrong net ETH");
        assertEq(afterFees - beforeFees, expectedFee, "wrong ETH fee");
        assertGt(afterUserDeposit - beforeUserDeposit, 0, "no tokens credited");

        vm.stopPrank();
    }
    
    /**
     * @notice Tests that a blacklisted user cannot buy with ETH.
     */
    function test_buyWithETH_revertsIfBlacklisted() public {
        vm.startPrank(owner);
        presale.blacklist(user);
        vm.stopPrank();

        vm.startPrank(user);
        vm.deal(user, 1 ether);
        vm.expectRevert(bytes("User is blacklisted"));
        presale.buyWithETH{value: 1 ether}();
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot buy with ETH if the presale is ended.
     */
    function test_buyWithETH_revertsIfPresaleInactive() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);
        vm.warp(_endingTime + 1 days);
        vm.expectRevert(bytes("Presale not started yet"));
        presale.buyWithETH{value: 1 ether}();
        vm.stopPrank();
    }

    /**
     * @notice Tests that a user cannot buy with ETH if the value is zero.
     */
    function test_buyWithETH_revertsIfValueIsZero() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);
        vm.expectRevert(bytes("Zero amount"));
        presale.buyWithETH{value: 0 wei}();
        vm.stopPrank();
    }

    /**
     * @notice Tests that buyWithETH correctly uses the oracle price to calculate token allocation.
     * @dev Uses MockAggregator with fixed ETH/USD price of $2000 (8 decimals → normalized to 18).
     */
    function test_buyWithETH_usesOraclePrice() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);

        uint256 beforeDeposit = presale.userTokensDeposited(user);

        presale.buyWithETH{value: 1 ether}();

        uint256 afterDeposit = presale.userTokensDeposited(user);

        // 1) Fee y net ETH
        uint256 expectedFee = (1 ether * presale.FEE_BPS()) / 10_000;
        uint256 netEth = 1 ether - expectedFee;

        // 2) El contrato multiplica *1e10 al precio del oráculo (8 → 18 decimales)
        uint256 ethPrice = 2000e18; // $2000 normalizado a 18 decimales
        uint256 usdValue = (netEth * ethPrice) / 1e18;

        // 3) Cálculo de tokens a recibir
        uint256 expectedTokens = usdValue * 1e6 / presale.phases(0,1);

        assertEq(afterDeposit - beforeDeposit, expectedTokens, "wrong token allocation");

        vm.stopPrank();
    }

    /**
     * @notice Tests that a user can successfully claim tokens after the presale ends.
     */
    function test_claimTokens() public {
        vm.startPrank(owner);
        flyToken.approve(address(presale), 1_000_000e18);
        presale.depositSaleTokens(1_000_000e18);
        vm.stopPrank();

        deal(_usdtAddress, user, 1_000e6); 
        vm.startPrank(user);
        IERC20(_usdtAddress).approve(address(presale), 1_000e6);
        presale.buyWithTokens(_usdtAddress, 1_000e6);

        vm.warp(_endingTime + 1);

        uint256 beforeBalance = flyToken.balanceOf(user);

        presale.claimTokens();

        uint256 afterBalance = flyToken.balanceOf(user);

        assertGt(afterBalance - beforeBalance, 0, "no tokens claimed");
        assertEq(presale.userTokensDeposited(user), 0, "allocation not cleared");

        vm.stopPrank();
    }


    /**
     * @notice Tests that claimTokens reverts if called before the presale ends.
     */
    function test_claimTokens_revertsIfClaimPeriodNotStarted() public {
        vm.startPrank(user);

        vm.expectRevert(bytes("Claim period not started"));
        presale.claimTokens();

        vm.stopPrank();
    }

    /**
     * @notice Tests that claimTokens reverts if the user has no tokens to claim.
     */
    function test_claimTokens_revertsIfUserClaimMoreTokens() public {
        vm.warp(_endingTime + 1);
        vm.startPrank(user);

        vm.expectRevert(bytes("Nothing to claim"));
        presale.claimTokens();

        vm.stopPrank();
    }

    /**
     * @notice Tests that the owner can withdraw ERC20 tokens in case of emergency.
     */
    function test_emergencyWithdrawTokens() public {
        vm.startPrank(owner);
        flyToken.transfer(address(presale), 1_000e18);
        uint256 beforeOwnerBalance = flyToken.balanceOf(owner);

        presale.emergencyWithdrawTokens(address(flyToken), 500e18);

        uint256 afterOwnerBalance = flyToken.balanceOf(owner);
        assertEq(afterOwnerBalance - beforeOwnerBalance, 500e18, "wrong withdrawn amount");
        vm.stopPrank();
    }

    /**
     * @notice Tests that non-owners cannot call emergencyWithdrawTokens.
     */
    function test_emergencyWithdrawTokens_revertsIfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        presale.emergencyWithdrawTokens(address(flyToken), 100e18);
        vm.stopPrank();
    }

    /**
     * @notice Tests that the owner can withdraw ETH in case of emergency.
     */
    function test_emergencyWithdrawETH() public {
        vm.deal(address(presale), 1 ether);

        uint256 beforeOwnerBalance = owner.balance;

        vm.startPrank(owner);
        presale.emergencyWithdrawETH();
        vm.stopPrank();

        uint256 afterOwnerBalance = owner.balance;
        assertEq(afterOwnerBalance - beforeOwnerBalance, 1 ether, "wrong ETH withdrawn");
    }

    /**
     * @notice Tests that non-owners cannot call emergencyWithdrawETH.
     */
    function test_emergencyWithdrawETH_revertsIfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert(); // Ownable revert
        presale.emergencyWithdrawETH();
        vm.stopPrank();
    }

    /**
     * @notice Tests that the owner can withdraw ERC20 fees after the presale ends.
     */
    function test_withdrawFees_Token() public {
        deal(_usdtAddress, user, 1_000e6);

        vm.startPrank(user);
        IERC20(_usdtAddress).approve(address(presale), 1_000e6);
        presale.buyWithTokens(_usdtAddress, 1_000e6);
        vm.stopPrank();

        vm.warp(_endingTime + 1);

        uint256 feesBefore = presale.collectedFees(_usdtAddress);
        uint256 beforeOwnerBalance = IERC20(_usdtAddress).balanceOf(owner);

        vm.startPrank(owner);
        presale.withdrawFees(_usdtAddress);
        vm.stopPrank();

        uint256 afterOwnerBalance = IERC20(_usdtAddress).balanceOf(owner);

        assertEq(afterOwnerBalance - beforeOwnerBalance, feesBefore, "wrong token fee amount");
        assertEq(presale.collectedFees(_usdtAddress), 0, "fees not cleared");
    }


    /**
     * @notice Tests that the owner can withdraw ETH fees after the presale ends.
     */
    function test_withdrawFees_ETH() public {
        vm.deal(user, 1 ether);

        vm.startPrank(user);
        presale.buyWithETH{value: 1 ether}();
        vm.stopPrank();

        vm.warp(_endingTime + 1);

        uint256 feesBefore = presale.collectedETHFees();
        uint256 beforeOwnerBalance = owner.balance;

        vm.startPrank(owner);
        presale.withdrawFees(address(0));
        vm.stopPrank();

        uint256 afterOwnerBalance = owner.balance;

        assertEq(afterOwnerBalance - beforeOwnerBalance, feesBefore, "wrong ETH fee amount");
        assertEq(presale.collectedETHFees(), 0, "ETH fees not cleared");
    }


    /**
     * @notice Tests that non-owners cannot call withdrawFees.
     */
    function test_withdrawFees_revertsIfNotOwner() public {
        vm.warp(_endingTime + 1);

        vm.startPrank(user);
        vm.expectRevert();
        presale.withdrawFees(_usdtAddress);
        vm.stopPrank();
    }

    /**
     * @notice Tests that withdrawFees reverts if called before the presale ends.
     */
    function test_withdrawFees_revertsIfClaimPeriodNotStarted() public {
        vm.startPrank(owner);
        vm.expectRevert(bytes("Claim period not started"));
        presale.withdrawFees(_usdtAddress);
        vm.stopPrank();
    }

}