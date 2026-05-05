// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";

contract DeployDAO is Script {
    uint256 public constant MIN_DELAY = 1 days; 

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        
        vm.startBroadcast(deployerKey);

        
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](0);
        TimelockController timelock = new TimelockController(
            MIN_DELAY,
            proposers,
            executors,
            deployer
        );
        console2.log("Timelock deployed at:", address(timelock));

        
        GovernanceToken token = new GovernanceToken(
            deployer, 
            deployer, 
            address(timelock), 
            deployer, 
            deployer
        );
        console2.log("Token deployed at:", address(token));

        TokenVesting vesting = new TokenVesting(
            address(token), 
            deployer, 
            uint64(block.timestamp), 
            365 days, 
            0
        );
        console2.log("Vesting deployed at:", address(vesting));
        
        
        token.transfer(address(vesting), 400_000_000 ether);

        
        MyGovernor governor = new MyGovernor(
            token, 
            timelock,
            7200,   
            50400,  
            0       
        );
        console2.log("Governor deployed at:", address(governor));

        
        Treasury treasury = new Treasury(deployer);
        treasury.transferOwnership(address(timelock));
        console2.log("Treasury deployed at:", address(treasury));

        
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE(); 

        
        timelock.grantRole(proposerRole, address(governor));
        
        timelock.grantRole(executorRole, address(0));
        
        timelock.renounceRole(adminRole, deployer);

        vm.stopBroadcast();
    }
}