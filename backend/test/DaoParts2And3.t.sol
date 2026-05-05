// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {Box} from "../src/Box.sol";
import {FeeSettings} from "../src/FeeSettings.sol";
import {UpgradeableBoxV1} from "../src/UpgradeableBoxV1.sol";
import {UpgradeableBoxV2} from "../src/UpgradeableBoxV2.sol";
import {UpgradeableBoxProxy} from "../src/UpgradeableBoxProxy.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IGovernor} from "openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVotes} from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

contract DaoParts2And3Test is Test {
    address internal owner = address(0x1001);
    address internal teamVesting = address(0x1002);
    address internal community = address(0x1003);
    address internal liquidity = address(0x1004);
    address internal recipient = address(0x1005);

    uint48 internal constant TEST_VOTING_DELAY = 1;
    uint32 internal constant TEST_VOTING_PERIOD = 20;
    uint256 internal constant TEST_TIMELOCK_DELAY = 60;
    uint256 internal constant PROPOSAL_THRESHOLD = 10_000_000 ether; // 1% of 1,000,000,000 GOV

    GovernanceToken internal token;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;
    Box internal box;
    FeeSettings internal feeSettings;

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(teamVesting, 100 ether);
        vm.deal(community, 100 ether);
        vm.deal(liquidity, 100 ether);
        vm.deal(recipient, 0 ether);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        vm.startPrank(owner);
        timelock = new TimelockController(TEST_TIMELOCK_DELAY, proposers, executors, owner);
        treasury = new Treasury(address(timelock));

        token = new GovernanceToken(
            owner,
            teamVesting,
            address(treasury),
            community,
            liquidity
        );

        governor = new MyGovernor(
            IVotes(address(token)),
            timelock,
            TEST_VOTING_DELAY,
            TEST_VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), owner);

        box = new Box(address(timelock));
        feeSettings = new FeeSettings(address(timelock), 100);
        vm.stopPrank();

        vm.prank(teamVesting);
        token.delegate(teamVesting);

        vm.prank(community);
        token.delegate(community);

        vm.prank(liquidity);
        token.delegate(liquidity);

        vm.roll(block.number + 1);
    }

    function _singleAction(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);

        targets[0] = target;
        values[0] = value;
        calldatas[0] = data;
    }

    function _propose(address proposer, address target, uint256 value, bytes memory data, string memory description)
        internal
        returns (uint256 proposalId, bytes32 descriptionHash)
    {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _singleAction(target, value, data);

        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, description);
        descriptionHash = keccak256(bytes(description));
    }

    function _moveToVotingPeriod() internal {
        vm.roll(block.number + governor.votingDelay() + 1);
    }

    function _movePastVotingPeriod() internal {
        vm.roll(block.number + governor.votingPeriod() + 1);
    }

    function _queueAndExecute(address target, uint256 value, bytes memory data, bytes32 descriptionHash) internal {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _singleAction(target, value, data);

        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + TEST_TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descriptionHash);
    }

    function _passProposal(address voter, uint256 proposalId) internal {
        _moveToVotingPeriod();
        vm.prank(voter);
        governor.castVote(proposalId, 1); // 1 = For
        _movePastVotingPeriod();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function _deployUpgradeableBox() internal returns (UpgradeableBoxV1 upgradeableBox) {
        UpgradeableBoxV1 implementationV1 = new UpgradeableBoxV1();
        bytes memory initData = abi.encodeWithSelector(UpgradeableBoxV1.initialize.selector, address(timelock));
        UpgradeableBoxProxy proxy = new UpgradeableBoxProxy(address(implementationV1), initData);
        upgradeableBox = UpgradeableBoxV1(address(proxy));
    }

    function testGovernorVotingConfiguration() public view {
        assertEq(governor.votingDelay(), TEST_VOTING_DELAY);
        assertEq(governor.votingPeriod(), TEST_VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function testQuorumIsFourPercentOfTotalSupply() public view {
        assertEq(governor.quorum(block.number - 1), 40_000_000 ether);
    }

    function testGovernorIsConnectedToTimelock() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    function testGovernorIsSoleProposerInTimelock() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), owner));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testAnyoneCanTriggerQueuedTimelockExecution() public view {
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
    }

    function testTimelockOwnsControlledContracts() public view {
        assertEq(treasury.owner(), address(timelock));
        assertEq(box.owner(), address(timelock));
        assertEq(feeSettings.owner(), address(timelock));
    }

    function testFullLifecycleBoxStore42() public {
        bytes memory data = abi.encodeWithSelector(Box.store.selector, 42);
        string memory description = "Proposal: call Box.store(42)";

        console2.log("STEP 1 - Create proposal: Box.store(42)");
        (uint256 proposalId, bytes32 descriptionHash) = _propose(teamVesting, address(box), 0, data, description);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        console2.log("STEP 2 - Vote for proposal");
        _passProposal(teamVesting, proposalId);

        console2.log("STEP 3 - Queue proposal in Timelock");
        console2.log("STEP 4 - Execute proposal after Timelock delay");
        _queueAndExecute(address(box), 0, data, descriptionHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(box.retrieve(), 42);
        console2.log("Box value:", box.retrieve());
    }

    function testTransfersERC20TokensFromTreasuryViaGovernance() public {
        uint256 amount = 1_000 ether;
        uint256 beforeBalance = token.balanceOf(recipient);

        bytes memory data = abi.encodeWithSelector(Treasury.releaseToken.selector, IERC20(address(token)), recipient, amount);
        (uint256 proposalId, bytes32 descriptionHash) = _propose(teamVesting, address(treasury), 0, data, "Transfer GOV from Treasury");

        _passProposal(teamVesting, proposalId);
        _queueAndExecute(address(treasury), 0, data, descriptionHash);

        assertEq(token.balanceOf(recipient), beforeBalance + amount);
    }

    function testTransfersETHFromTreasuryViaGovernance() public {
        vm.deal(address(treasury), 5 ether);
        uint256 beforeBalance = recipient.balance;

        bytes memory data = abi.encodeWithSelector(Treasury.releaseEth.selector, payable(recipient), 1 ether);
        (uint256 proposalId, bytes32 descriptionHash) = _propose(teamVesting, address(treasury), 0, data, "Transfer ETH from Treasury");

        _passProposal(teamVesting, proposalId);
        _queueAndExecute(address(treasury), 0, data, descriptionHash);

        assertEq(recipient.balance, beforeBalance + 1 ether);
    }

    function testChangesParameterThroughGovernance() public {
        bytes memory data = abi.encodeWithSelector(FeeSettings.setFeeBps.selector, 250);
        (uint256 proposalId, bytes32 descriptionHash) = _propose(teamVesting, address(feeSettings), 0, data, "Change fee to 250 bps");

        _passProposal(teamVesting, proposalId);
        _queueAndExecute(address(feeSettings), 0, data, descriptionHash);

        assertEq(feeSettings.feeBps(), 250);
    }

    function testDelegateeVotesUsingDelegatedVotingPower() public {
        vm.prank(teamVesting);
        token.delegate(community);
        vm.roll(block.number + 1);

        assertEq(token.getVotes(community), 600_000_000 ether);

        bytes memory data = abi.encodeWithSelector(Box.store.selector, 77);
        (uint256 proposalId, bytes32 descriptionHash) = _propose(community, address(box), 0, data, "Delegatee votes with delegated power");

        _moveToVotingPeriod();
        vm.prank(community);
        governor.castVote(proposalId, 1);
        _movePastVotingPeriod();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
        _queueAndExecute(address(box), 0, data, descriptionHash);
        assertEq(box.retrieve(), 77);
    }

    function testProposalDefeatedWhenQuorumIsNotMet() public {
        bytes memory data = abi.encodeWithSelector(Box.store.selector, 13);
        (uint256 proposalId,) = _propose(teamVesting, address(box), 0, data, "Proposal with no quorum");

        _moveToVotingPeriod();
        _movePastVotingPeriod();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function testProposalDefeatedWhenAgainstVotesWin() public {
        bytes memory data = abi.encodeWithSelector(Box.store.selector, 99);
        (uint256 proposalId,) = _propose(teamVesting, address(box), 0, data, "Proposal defeated by against votes");

        _moveToVotingPeriod();

        vm.prank(teamVesting);
        governor.castVote(proposalId, 0); // Against: 400M

        vm.prank(community);
        governor.castVote(proposalId, 1); // For: 200M

        _movePastVotingPeriod();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function testDirectBoxStoreCallIsBlocked() public {
        vm.expectRevert();
        vm.prank(teamVesting);
        box.store(42);
    }

    function testDirectTreasuryWithdrawalIsBlocked() public {
        vm.deal(address(treasury), 5 ether);

        vm.expectRevert();
        vm.prank(teamVesting);
        treasury.releaseEth(payable(recipient), 1 ether);
    }

    function testControlledContractUpgradeThroughTimelockGovernance() public {
        UpgradeableBoxV1 upgradeableBox = _deployUpgradeableBox();
        assertEq(upgradeableBox.owner(), address(timelock));
        assertEq(upgradeableBox.version(), "V1");

        UpgradeableBoxV2 implementationV2 = new UpgradeableBoxV2();
        bytes memory data = abi.encodeWithSelector(UpgradeableBoxV1.upgradeTo.selector, address(implementationV2));

        (uint256 proposalId, bytes32 descriptionHash) = _propose(
            teamVesting,
            address(upgradeableBox),
            0,
            data,
            "Upgrade controlled Box proxy from V1 to V2"
        );

        _passProposal(teamVesting, proposalId);
        _queueAndExecute(address(upgradeableBox), 0, data, descriptionHash);

        UpgradeableBoxV2 upgradedBox = UpgradeableBoxV2(address(upgradeableBox));
        assertEq(upgradedBox.version(), "V2");
    }

    function testDirectControlledContractUpgradeIsBlocked() public {
        UpgradeableBoxV1 upgradeableBox = _deployUpgradeableBox();
        UpgradeableBoxV2 implementationV2 = new UpgradeableBoxV2();

        vm.expectRevert(bytes("Only owner"));
        vm.prank(teamVesting);
        upgradeableBox.upgradeTo(address(implementationV2));
    }
}
