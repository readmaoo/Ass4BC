// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    event EtherReceived(address indexed sender, uint256 amount);
    event EtherReleased(address indexed to, uint256 amount);
    event TokenReleased(address indexed token, address indexed to, uint256 amount);
    event TargetExecuted(address indexed target, uint256 value, bytes data, bytes result);

    constructor(address timelock) Ownable(timelock) {
        require(timelock != address(0), "timelock zero");
    }

    receive() external payable {
        emit EtherReceived(msg.sender, msg.value);
    }

    function releaseETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "recipient zero");
        require(address(this).balance >= amount, "insufficient eth");

        (bool success, ) = to.call{value: amount}("");
        require(success, "eth transfer failed");

        emit EtherReleased(to, amount);
    }

    function releaseToken(IERC20 token, address to, uint256 amount) external onlyOwner {
        require(address(token) != address(0), "token zero");
        require(to != address(0), "recipient zero");

        token.safeTransfer(to, amount);
        emit TokenReleased(address(token), to, amount);
    }

    function execute(address target, uint256 value, bytes calldata data) external onlyOwner returns (bytes memory) {
        require(target != address(0), "target zero");

        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "target call failed");

        emit TargetExecuted(target, value, data, result);
        return result;
    }
}
