// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {Box} from "../src/Box.sol";
import {FeeSettings} from "../src/FeeSettings.sol";

import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {IVotes} from "openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

contract DeployParts2And3 is Script {
    uint256 public constant TIMELOCK_DELAY = 2 days;
    uint48 public constant VOTING_DELAY_BLOCKS = 7200; // ~1 day if block time is ~12 sec
    uint32 public constant VOTING_PERIOD_BLOCKS = 50400; // ~1 week if block time is ~12 sec
    uint256 public constant PROPOSAL_THRESHOLD = 10_000_000 ether; // 1% of 1B supply

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address teamVesting = vm.envOr("TEAM_VESTING", deployer);
        address communityAirdrop = vm.envOr("COMMUNITY_AIRDROP", deployer);
        address liquidity = vm.envOr("LIQUIDITY", deployer);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);

        vm.startBroadcast(deployerPrivateKey);

        TimelockController timelock = new TimelockController(
            TIMELOCK_DELAY,
            proposers,
            executors,
            deployer
        );

        Treasury treasury = new Treasury(address(timelock));

        GovernanceToken token = new GovernanceToken(
            deployer,
            teamVesting,
            address(treasury),
            communityAirdrop,
            liquidity
        );

        MyGovernor governor = new MyGovernor(
            IVotes(address(token)),
            timelock,
            VOTING_DELAY_BLOCKS,
            VOTING_PERIOD_BLOCKS,
            PROPOSAL_THRESHOLD
        );

        Box box = new Box(address(timelock));
        FeeSettings feeSettings = new FeeSettings(address(timelock), 100);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        console2.log("GovernanceToken:", address(token));
        console2.log("MyGovernor:", address(governor));
        console2.log("TimelockController:", address(timelock));
        console2.log("Treasury:", address(treasury));
        console2.log("Box:", address(box));
        console2.log("FeeSettings:", address(feeSettings));
    }
}
