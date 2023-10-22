// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ISubscription {
    /**
     * @notice Emits when a subscription is successfully created.
     */
    event CreateSubscription(
        uint256 indexed subscriptionId,
        address indexed sender,
        address indexed recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint256 interval,
        uint256 fixedRate
    );

    /**
     * @notice Emits when the recipient of a subscription withdraws a portion or all their pro rata share of the subscription.
     */
    event WithdrawFromRecipient(uint256 indexed subscriptionId, address indexed recipient, uint256 amount);

    /**
     * @notice Emits when the sender of a subscription withdraws the remain balance.
     */
    event WithdrawFromSender(uint256 indexed subscriptionId, address indexed sender, uint256 amount);

    /**
     * @notice Emits when the sender of a subscription deposte a portion.
     */
    event DepositeFromSender(uint256 indexed subscriptionId, address indexed sender, uint256 amount);

    /**
     * @notice Emits when a subscription is successfully cancelled and tokens are transferred back on a pro rata basis.
     */
    event CancelSubscription(
        uint256 indexed subscriptionId,
        address indexed sender,
        address indexed recipient,
        uint256 senderBalance,
        uint256 recipientBalance
    );

    function getSubscription(uint256 subscriptionId)
        external
        view
        returns (
            address sender,
            address recipient,
            uint256 deposit,
            address tokenAddress,
            uint256 startTime,
            uint256 stopTime,
            uint256 interval,
            uint256 remainingBalance,
            uint256 lastWithdrawTime,
            uint256 withdrawCount,
            uint256 fixedRate
        );

    function createSubscription(
        address recipient, 
        uint256 deposit, 
        address tokenAddress, 
        uint256 startTime, 
        uint256 stopTime, 
        uint256 interval,
        uint256 fixedRate
    )   external;

    function withdrawFromRecipient(uint256 subscriptionId, uint256 funds) external returns (bool);
    
    function withdrawFromSender(uint256 subscriptionId, uint256 funds) external returns (bool);

    function depositeFromSender(uint256 subscriptionId, uint256 funds) external returns (bool);

    function cancelSubscription(uint256 subscriptionId) external returns (bool);
}