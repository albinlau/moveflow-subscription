// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {ISubscription} from "./interfaces/ISubscription.sol";
import {Struct} from "./library/Struct.sol";
import {CarefulMath} from "./CarefulMath.sol";

contract Subscription is ISubscription, ReentrancyGuard, CarefulMath {
    using SafeERC20 for IERC20;

    /*** Storage Properties ***/

    /**
     * @notice Counter for new subscription ids.
     */
    uint256 public nextSubscriptionId;

    /**
     * @notice The subscription objects identifiable by their unsigned integer ids.
     */
    mapping(uint256 => Struct.Subscription) private subscriptions;

    /*** Modifiers ***/

    /**
     * @dev Throws if the caller is not the sender of the recipient of the subscription.
     */
    modifier onlySenderOrRecipient(uint256 subscriptionId) {
        require(
            msg.sender == subscriptions[subscriptionId].sender || msg.sender == subscriptions[subscriptionId].recipient,
            "caller is not the sender or the recipient of the subscription"
        );
        _;
    }

    /**
     * @dev Throws if the caller is not the recipient of the subscription.
     */
    modifier onlyRecipient(uint256 subscriptionId) {
        require(
            msg.sender == subscriptions[subscriptionId].recipient,
            "caller is not the recipient of the subscription"
        );
        _;
    }

    /**
     * @dev Throws if the caller is not the sender of the subscription.
     */
    modifier onlySender(uint256 subscriptionId) {
        require(
            msg.sender == subscriptions[subscriptionId].sender,
            "caller is not the sender of the subscription"
        );
        _;
    }

    /**
     * @dev Throws if the provided id does not point to a valid subscription.
     */
    modifier subscriptionExists(uint256 subscriptionId) {
        require(subscriptions[subscriptionId].isEntity, "subscription does not exist");
        _;
    }

    /*** Contract Logic Starts Here */

    constructor() {        
        nextSubscriptionId = 500000;
    }

    /*** View Functions ***/

    /**
     * @notice Returns the subscription with all its properties.
     * @dev Throws if the id does not point to a valid subscription.
     * @param subscriptionId The id of the subscription to query.
     */
    function getSubscription(uint256 subscriptionId)
        public
        view
        subscriptionExists(subscriptionId)
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
        )
    {
        sender = subscriptions[subscriptionId].sender;
        recipient = subscriptions[subscriptionId].recipient;
        deposit = subscriptions[subscriptionId].deposit;
        tokenAddress = subscriptions[subscriptionId].tokenAddress;
        startTime = subscriptions[subscriptionId].startTime;
        stopTime = subscriptions[subscriptionId].stopTime;
        interval = subscriptions[subscriptionId].interval;
        remainingBalance = subscriptions[subscriptionId].remainingBalance;
        lastWithdrawTime = subscriptions[subscriptionId].lastWithdrawTime;
        withdrawCount = subscriptions[subscriptionId].withdrawCount;
        fixedRate = subscriptions[subscriptionId].fixedRate;
    }

    /**
     * @notice Returns either the delta in seconds between `block.timestamp` and `startTime` or
     *  between `stopTime` and `startTime, whichever is smaller. If `block.timestamp` is before
     *  `startTime`, it returns 0.
     * @dev Throws if the id does not point to a valid subscription.
     * @param subscriptionId The id of the subscription for which to query the delta.
     * @return delta The time delta in seconds.
     */
    function deltaOf(uint256 subscriptionId) public view subscriptionExists(subscriptionId) returns (uint256 delta) {
        Struct.Subscription memory subscription = subscriptions[subscriptionId];
        if (block.timestamp <= subscription.startTime) return 0;
        if (block.timestamp < subscription.stopTime) return block.timestamp - subscription.lastWithdrawTime;
        return subscription.stopTime - subscription.lastWithdrawTime;
    }

    /**
     * @notice the right of withdtraw for ricipient.
     * @dev Throws if the id does not point to a valid subscription.
     * @param subscriptionId The id of the subscription for which to query the streamed amount.
     */
    function checkWithdrawFromRecipient(uint256 subscriptionId) public view subscriptionExists(subscriptionId) returns (bool) {
        Struct.Subscription memory subscription = subscriptions[subscriptionId];
        if (block.timestamp <= subscription.startTime) return false;
        if (block.timestamp < subscription.stopTime) 
            return (block.timestamp - subscription.startTime)/subscription.interval > subscription.withdrawCount;
        return (subscription.stopTime - subscription.startTime)/subscription.interval > subscription.withdrawCount;
    }

    /**
     * @notice the right of withdtraw for sender.
     * @dev Throws if the id does not point to a valid subscription.
     * @param subscriptionId The id of the subscription for which to query the streamed amount.
     */
    function checkWithdrawFromSender(uint256 subscriptionId) public view subscriptionExists(subscriptionId) returns (bool) {
        Struct.Subscription memory subscription = subscriptions[subscriptionId];
        uint256 totalIntervals = (subscription.stopTime - subscription.startTime)/subscription.interval;
        return totalIntervals == subscription.withdrawCount;
    }

    /*** Public Effects & Interactions Functions ***/

    struct CreateSubscriptionLocalVars {
        MathError mathErr;
        uint256 duration;
        uint256 interval;
    }

    /**
     * @notice Creates a new subscription funded by `msg.sender` and paid towards `recipient`.
     * @dev Throws if the recipient is the zero address, the contract itself or the caller.
     *  Throws if the deposit is 0.
     *  Throws if the start time is before `block.timestamp`.
     *  Throws if the stop time is before the start time.
     *  Throws if the duration calculation has a math error.
     *  Throws if the deposit is smaller than the duration.
     *  Throws if the deposit is not a multiple of the duration.
     *  Throws if the rate calculation has a math error.
     *  Throws if the next subscription id calculation has a math error.
     *  Throws if the contract is not allowed to transfer enough tokens.
     *  Throws if there is a token transfer failure.
     * @param recipient The address towards which the money is subscriptioned.
     * @param deposit The amount of money to be subscriptioned.
     * @param tokenAddress The ERC20 token to use as subscriptioning currency.
     * @param startTime The unix timestamp for when the subscription starts.
     * @param stopTime The unix timestamp for when the subscription stops.
     * @param interval The time in seconds between each subscription payment.
     * @param fixedRate The fixed rate of the subscription.
     */
    function createSubscription(
        address recipient, 
        uint256 deposit, 
        address tokenAddress, 
        uint256 startTime, 
        uint256 stopTime, 
        uint256 interval, 
        uint256 fixedRate
    )   
        public
    {
        require(recipient != address(0x00), "subscription to the zero address");
        require(recipient != address(this), "subscription to the contract itself");
        require(recipient != msg.sender, "subscription to the caller");
        require(deposit > 0, "deposit is zero");
        require(startTime >= block.timestamp, "start time before block.timestamp");
        require(stopTime > startTime, "stop time before the start time");

        CreateSubscriptionLocalVars memory vars;
        (vars.mathErr, vars.duration) = subUInt(stopTime, startTime);
        /* `subUInt` can only return MathError.INTEGER_UNDERFLOW but we know `stopTime` is higher than `startTime`. */
        assert(vars.mathErr == MathError.NO_ERROR);

        /* Create and store the subscription object. */
        uint256 subscriptionId = nextSubscriptionId;
        subscriptions[subscriptionId] = Struct.Subscription({
            deposit: deposit,
            fixedRate: fixedRate,
            remainingBalance: deposit,
            startTime: startTime,
            stopTime: stopTime,
            interval: interval,
            withdrawCount: 0,
            lastWithdrawTime: startTime,
            recipient: recipient,
            sender: msg.sender,
            tokenAddress: tokenAddress,
            isEntity: true
        });

        /* Increment the next subscription id. */
        (vars.mathErr, nextSubscriptionId) = addUInt(nextSubscriptionId, uint256(1));
        require(vars.mathErr == MathError.NO_ERROR, "next subscription id calculation error");

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), deposit);
        emit CreateSubscription(subscriptionId, msg.sender, recipient, deposit, tokenAddress, startTime, stopTime, interval, fixedRate);
    }

    /**
     * @notice Withdraws from the contract to the recipient's account.
     * @dev Throws if the id does not point to a valid subscription.
     *  Throws if the caller is the recipient of the subscription.
     *  Throws if the amount exceeds the available balance.
     *  Throws if there is a token transfer failure.
     * @param subscriptionId The id of the subscription to withdraw tokens from.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawFromRecipient(uint256 subscriptionId, uint256 amount)
        external
        nonReentrant
        subscriptionExists(subscriptionId)
        onlyRecipient(subscriptionId)
        returns (bool)
    {
        Struct.Subscription memory subscription = subscriptions[subscriptionId];

        if (subscription.fixedRate > 0) {
            amount = subscription.fixedRate;
        }
        require(amount > 0, "amount is zero");

        require(subscription.remainingBalance >= amount, "amount exceeds the available balance");
        require(checkWithdrawFromRecipient(subscriptionId), "withdrawal not allowed");

        MathError mathErr;
        (mathErr, subscriptions[subscriptionId].remainingBalance) = subUInt(subscription.remainingBalance, amount);
        /**
         * `subUInt` can only return MathError.INTEGER_UNDERFLOW but we know that `remainingBalance` is at least
         * as big as `amount`.
         */
        assert(mathErr == MathError.NO_ERROR);

        (mathErr, subscriptions[subscriptionId].withdrawCount) = addUInt(subscription.withdrawCount, uint256(1));
        assert(mathErr == MathError.NO_ERROR);

        if (subscriptions[subscriptionId].remainingBalance == 0) {
            delete subscriptions[subscriptionId];
        }

        IERC20(subscription.tokenAddress).safeTransfer(subscription.recipient, amount);
        emit WithdrawFromRecipient(subscriptionId, subscription.recipient, amount);
        return true;
    }

    /**
     * @notice Withdraws from the contract to the sender's account.
     * @dev Throws if the id does not point to a valid subscription.
     *  Throws if the caller is not the sender of the subscription.
     *  Throws if the amount exceeds the available balance.
     *  Throws if there is a token transfer failure.
     * @param subscriptionId The id of the subscription to withdraw tokens from.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawFromSender(uint256 subscriptionId, uint256 amount)
        external
        nonReentrant
        subscriptionExists(subscriptionId)
        onlySender(subscriptionId)
        returns (bool)
    {
        require(amount > 0, "amount is zero");
        Struct.Subscription memory subscription = subscriptions[subscriptionId];

        require(subscription.remainingBalance >= amount, "amount exceeds the available balance");
        require(checkWithdrawFromSender(subscriptionId), "withdrawal not allowed");

        MathError mathErr;
        (mathErr, subscriptions[subscriptionId].remainingBalance) = subUInt(subscription.remainingBalance, amount);
        /**
         * `subUInt` can only return MathError.INTEGER_UNDERFLOW but we know that `remainingBalance` is at least
         * as big as `amount`.
         */
        assert(mathErr == MathError.NO_ERROR);

        (mathErr, subscriptions[subscriptionId].deposit) = subUInt(subscription.deposit, amount);
        assert(mathErr == MathError.NO_ERROR);

        if (subscriptions[subscriptionId].remainingBalance == 0) {
            delete subscriptions[subscriptionId];
        }

        IERC20(subscription.tokenAddress).safeTransfer(msg.sender, amount);
        emit WithdrawFromSender(subscriptionId, msg.sender, amount);
        return true;
    }

    /**
     * @notice Deposite from the sender's account.
     * @dev Throws if the id does not point to a valid subscription.
     *  Throws if the caller is not the sender of the subscription.
     *  Throws if there is a token transfer failure.
     * @param subscriptionId The id of the subscription to withdraw tokens from.
     * @param amount The amount of tokens to withdraw.
     */
    function depositeFromSender(uint256 subscriptionId, uint256 amount)
        external
        nonReentrant
        subscriptionExists(subscriptionId)
        onlySender(subscriptionId)
        returns (bool)
    {
        require(amount > 0, "amount is zero");
        Struct.Subscription memory subscription = subscriptions[subscriptionId];

        MathError mathErr;
        (mathErr, subscriptions[subscriptionId].remainingBalance) = addUInt(subscription.remainingBalance, amount);
        assert(mathErr == MathError.NO_ERROR);

        (mathErr, subscriptions[subscriptionId].deposit) = addUInt(subscription.deposit, amount);
        assert(mathErr == MathError.NO_ERROR);

        IERC20(subscription.tokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositeFromSender(subscriptionId, msg.sender, amount);
        return true;
    }

    /**
     * @notice Cancels the subscription and transfers the tokens back on a pro rata basis.
     * @dev Throws if the id does not point to a valid subscription.
     *  Throws if the caller is not the sender or the recipient of the subscription.
     *  Throws if there is a token transfer failure.
     * @param subscriptionId The id of the subscription to cancel.
     * @return bool true=success, otherwise false.
     */
    function cancelSubscription(uint256 subscriptionId)
        external
        nonReentrant
        subscriptionExists(subscriptionId)
        onlySenderOrRecipient(subscriptionId)
        returns (bool)
    {
        Struct.Subscription memory subscription = subscriptions[subscriptionId];

        require(
            (block.timestamp - subscription.startTime)/subscription.interval == subscription.withdrawCount, 
            "subscription not allowed to cancel"
        );

        uint256 senderBalance = subscription.remainingBalance;

        delete subscriptions[subscriptionId];

        IERC20(subscription.tokenAddress).safeTransfer(subscription.sender, senderBalance);

        emit CancelSubscription(subscriptionId, subscription.sender, subscription.recipient, 0, senderBalance);
        return true;
    }
}