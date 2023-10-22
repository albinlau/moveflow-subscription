// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

library Struct {
    struct Stream {
        uint256 deposit;
        uint256 ratePerInterval;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime;
        uint256 interval;
        uint256 lastWithdrawTime;
        address recipient;
        address sender;
        address tokenAddress;
        bool isEntity;
    }

    struct Subscription {
        uint256 deposit;
        uint256 fixedRate;
        uint256 remainingBalance;
        uint256 startTime;
        uint256 stopTime;
        uint256 interval;
        uint256 withdrawCount;
        uint256 lastWithdrawTime;
        address recipient;
        address sender;
        address tokenAddress;
        bool isEntity;
    }
}