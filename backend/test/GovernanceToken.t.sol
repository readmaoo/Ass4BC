// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

contract GovernanceTokenTest is Test {
    GovernanceToken token;
    TokenVesting vesting;

    uint256 ownerPk = 0xA11CE;
    uint256 alicePk = 0xB0B;
    uint256 bobPk = 0xCAFE;
    uint256 treasuryPk = 0x100;
    uint256 communityPk = 0x200;
    uint256 liquidityPk = 0x300;

    address owner;
    address alice;
    address bob;
    address treasury;
    address community;
    address liquidity;

    uint64 start;
    uint64 constant DURATION = 365 days;

    function setUp() public {
        owner = vm.addr(ownerPk);
        alice = vm.addr(alicePk);
        bob = vm.addr(bobPk);
        treasury = vm.addr(treasuryPk);
        community = vm.addr(communityPk);
        liquidity = vm.addr(liquidityPk);
        start = uint64(block.timestamp);

        vesting = new TokenVesting(address(0xdead), owner, start, DURATION, 0);
        token = new GovernanceToken(owner, address(vesting), treasury, community, liquidity);
        vesting = new TokenVesting(address(token), owner, start, DURATION, 0);
        token = new GovernanceToken(owner, address(vesting), treasury, community, liquidity);
    }

    function testInitialDistribution() public {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(vesting)), 400_000_000 ether);
        assertEq(token.balanceOf(treasury), 300_000_000 ether);
        assertEq(token.balanceOf(community), 200_000_000 ether);
        assertEq(token.balanceOf(liquidity), 100_000_000 ether);
    }

    function testSelfDelegationGivesVotes() public {
        vm.prank(treasury);
        token.delegate(treasury);
        assertEq(token.getVotes(treasury), 300_000_000 ether);
    }

    function testDelegationMovesVotes() public {
        vm.startPrank(treasury);
        token.delegate(treasury);
        token.transfer(alice, 50_000_000 ether);
        vm.stopPrank();
        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(treasury), 250_000_000 ether);
        assertEq(token.getVotes(alice), 50_000_000 ether);
    }

    function testPastVotesSnapshotBeforeTransfer() public {
        vm.prank(treasury);
        token.delegate(treasury);
        uint256 snap = block.number;
        vm.roll(block.number + 1);
        vm.prank(treasury);
        token.transfer(alice, 10_000_000 ether);
        assertEq(token.getPastVotes(treasury, snap), 300_000_000 ether);
        assertEq(token.getVotes(treasury), 290_000_000 ether);
    }

    function testPastTotalSupplySnapshot() public {
        uint256 snap = block.number;
        vm.roll(block.number + 1);
        assertEq(token.getPastTotalSupply(snap), 1_000_000_000 ether);
    }

    function testPermitSetsAllowance() public {
        uint256 value = 1_234 ether;
        uint256 deadline = block.timestamp + 1 days;
       bytes32 digest = keccak256(abi.encodePacked(
       "\x19\x01", 
    token.DOMAIN_SEPARATOR(), 
    keccak256(abi.encode(
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
        treasury,
        alice,
        value,
        token.nonces(treasury),
        deadline
    ))
));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(treasuryPk, digest);
        token.permit(treasury, alice, value, deadline, v, r, s);
        assertEq(token.allowance(treasury, alice), value);
    }

        function testPermitReplayFails() public {
        uint256 value = 500 ether;
        uint256 deadline = block.timestamp + 1 days;
        
        // We use owner, ownerPk, and token.nonces(owner) here
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01", 
            token.DOMAIN_SEPARATOR(), 
            keccak256(abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,  // <-- This MUST match the owner in vm.sign and token.permit
                alice,
                value,
                token.nonces(owner), // <-- This MUST match the owner in vm.sign
                deadline
            ))
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        
        token.permit(owner, alice, value, deadline, v, r, s);
        vm.expectRevert();
        token.permit(owner, alice, value, deadline, v, r, s);
    }

        function testVestingReleasesHalfway() public {
        // 1. Deploy the token, but mint the team tokens to the owner initially
        GovernanceToken t = new GovernanceToken(owner, owner, treasury, community, liquidity);
        
        // 2. Deploy the vesting contract 
        TokenVesting v = new TokenVesting(address(t), owner, start, DURATION, 0);
        
        // 3. Manually fund the vesting contract so it actually holds the tokens
        vm.prank(owner);
        t.transfer(address(v), 400_000_000 ether);

        vm.warp(start + DURATION / 2);
        assertApproxEqAbs(v.releasable(), 200_000_000 ether, 2);
        vm.prank(owner);
        v.release();
        assertApproxEqAbs(t.balanceOf(owner), 200_000_000 ether, 2);
    }

    function testVestingNothingBeforeStart() public {
        TokenVesting v = new TokenVesting(address(token), owner, start + 10 days, DURATION, 0);
        new GovernanceToken(owner, address(v), treasury, community, liquidity);
        assertEq(v.releasable(), 0);
        vm.expectRevert(TokenVesting.NoTokensDue.selector);
        v.release();
    }

        function testVestingFullyReleasesAfterDuration() public {
        GovernanceToken t = new GovernanceToken(owner, owner, treasury, community, liquidity);
        TokenVesting v = new TokenVesting(address(t), owner, start, DURATION, 0);
        
        vm.prank(owner);
        t.transfer(address(v), 400_000_000 ether);

        vm.warp(start + DURATION + 1);
        vm.prank(owner);
        v.release();
        assertEq(t.balanceOf(owner), 400_000_000 ether);
        assertEq(v.releasable(), 0);
    }
}
