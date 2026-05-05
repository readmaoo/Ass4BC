// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    event ETHReleased(address indexed to, uint256 amount);
    event TokenReleased(address indexed token, address indexed to, uint256 amount);
    event CallExecuted(address indexed target, uint256 value, bytes data, bytes result);

    constructor(address timelock) Ownable(timelock) {
        require(timelock != address(0), "timelock zero");
    }

    receive() external payable {}

    function releaseEth(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "recipient zero");
        require(address(this).balance >= amount, "insufficient ETH");

        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit ETHReleased(to, amount);
    }

    function releaseToken(IERC20 token, address to, uint256 amount) external onlyOwner {
        require(address(token) != address(0), "token zero");
        require(to != address(0), "recipient zero");

        bool ok = token.transfer(to, amount);
        require(ok, "token transfer failed");

        emit TokenReleased(address(token), to, amount);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (bytes memory result)
    {
        require(target != address(0), "target zero");

        (bool ok, bytes memory response) = target.call{value: value}(data);
        require(ok, "call failed");

        emit CallExecuted(target, value, data, response);
        return response;
    }
}
