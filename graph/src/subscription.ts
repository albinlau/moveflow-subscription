import { Address, BigInt, store, log } from "@graphprotocol/graph-ts";

import {
  CancelSubscription,
  CreateSubscription,
  DepositeFromSender,
  WithdrawFromRecipient,
  WithdrawFromSender,
} from "../../generated/Subscription/ISubscription";
import { Recipient, RecipientWithdrawLog, Sender, SenderDepositeLog, SenderWithdrawLog, SubscriptionList } from "../../generated/schema";

export function handleCreateSubscription(event: CreateSubscription): void {
  let subscription = SubscriptionList.load(event.params.subscriptionId.toHex());
  if (subscription) {
    log.error("[handleCreateSubscription]SubscriptionList already exists {}", [event.params.subscriptionId.toHex()]);
  } else {
    subscription = new SubscriptionList(event.params.subscriptionId.toHex());
  }

  subscription.deposit = event.params.deposit;
  subscription.fixedRate = event.params.fixedRate;
  subscription.withdrawnBalance = BigInt.fromI32(0);
  subscription.remainingBalance = event.params.deposit;
  subscription.startTime = event.params.startTime;
  subscription.stopTime = event.params.stopTime;
  subscription.interval = event.params.interval;
  subscription.withdrawableCount = event.params.stopTime.minus(event.params.startTime).div(event.params.interval);
  subscription.withdrawnCount = BigInt.fromI32(0);
  subscription.lastWithdrawTime = event.params.startTime;
  subscription.tokenAddress = event.params.tokenAddress;
  subscription.isEntity = true;

  let recipient = Recipient.load(event.params.recipient.toHex());
  if (!recipient) {
    recipient = new Recipient(event.params.recipient.toHex());
    recipient.withdrawnBalance = BigInt.fromI32(0);
  }
  subscription.recipient = recipient.id;
  recipient.save();

  let sender = Sender.load(event.params.sender.toHex());
  if (!sender) {
    sender = new Sender(event.params.sender.toHex());
    sender.deposit = BigInt.fromI32(0);
    sender.withdrawnToRecipient = BigInt.fromI32(0);
  }
  subscription.sender = sender.id;
  sender.save();
  
  subscription.save();
}

export function handleWithdrawFromRecipient(event: WithdrawFromRecipient): void {
  let subscription = SubscriptionList.load(event.params.subscriptionId.toHex());
  if (!subscription) {
    log.error("[handleWithdrawFromRecipient]SubscriptionList does not exist {}", [event.params.subscriptionId.toHex()]);
    return;
  }
  subscription.remainingBalance = subscription.remainingBalance.minus(event.params.amount);
  subscription.withdrawnBalance = subscription.withdrawnBalance.plus(event.params.amount);
  subscription.withdrawnCount = subscription.withdrawnCount.plus(BigInt.fromI32(1));
  subscription.lastWithdrawTime = event.block.timestamp;

  let recipient = Recipient.load(event.params.recipient.toHex());
  if (!recipient) {
    log.error("[handleWithdrawFromRecipient]Recipient does not exist {}", [event.params.recipient.toHex()]);
    return;
  }
  recipient.withdrawnBalance = recipient.withdrawnBalance.plus(event.params.amount);

  let sender = Sender.load(subscription.sender);
  if (!sender) {
    log.error("[handleWithdrawFromRecipient]Sender does not exist {}", [subscription.sender]);
    return;
  }
  sender.withdrawnToRecipient = sender.withdrawnToRecipient.plus(event.params.amount);

  let logId = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let recipientWithdrawLog = RecipientWithdrawLog.load(logId);
  if (recipientWithdrawLog) {
    log.error("[handleWithdrawFromRecipient]RecipientWithdrawLog already exists {}", [logId]);
  } else {
    recipientWithdrawLog = new RecipientWithdrawLog(logId);
  }
  recipientWithdrawLog.recipient = recipient.id;
  recipientWithdrawLog.subscription = subscription.id;
  recipientWithdrawLog.withdrawAmount = event.params.amount;
  recipientWithdrawLog.withdrawTime = event.block.timestamp;
  recipientWithdrawLog.withdrawnCount = subscription.withdrawnCount;

  recipient.save();
  sender.save();
  recipientWithdrawLog.save();
  subscription.save();
}

export function handleWithdrawFromSender(event: WithdrawFromSender): void {
  let subscription = SubscriptionList.load(event.params.subscriptionId.toHex());
  if (!subscription) {
    log.error("[handleWithdrawFromSender]SubscriptionList does not exist {}", [event.params.subscriptionId.toHex()]);
    return;
  }
  subscription.remainingBalance = subscription.remainingBalance.minus(event.params.amount);
  subscription.deposit = subscription.deposit.minus(event.params.amount);

  let sender = Sender.load(event.params.sender.toHex());
  if (!sender) {
    log.error("[handleWithdrawFromSender]Sender does not exist {}", [event.params.sender.toHex()]);
    return;
  }
  sender.deposit = sender.deposit.minus(event.params.amount);

  let logId = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let senderWithdrawLog = SenderWithdrawLog.load(logId);
  if (senderWithdrawLog) {
    log.error("[handleWithdrawFromSender]SenderWithdrawLog already exists {}", [logId]);
  } else {
    senderWithdrawLog = new SenderWithdrawLog(logId);
  }
  senderWithdrawLog.sender = sender.id;
  senderWithdrawLog.subscription = subscription.id;
  senderWithdrawLog.withdrawAmount = event.params.amount;
  senderWithdrawLog.withdrawTime = event.block.timestamp;

  sender.save();
  senderWithdrawLog.save();
  subscription.save();
}

export function handleDepositeFromSender(event: DepositeFromSender): void {
  let subscription = SubscriptionList.load(event.params.subscriptionId.toHex());
  if (!subscription) {
    log.error("[handleDepositeFromSender]SubscriptionList does not exist {}", [event.params.subscriptionId.toHex()]);
    return;
  }
  subscription.deposit = subscription.deposit.plus(event.params.amount);
  subscription.remainingBalance = subscription.remainingBalance.plus(event.params.amount);

  let sender = Sender.load(event.params.sender.toHex());
  if (!sender) {
    log.error("[handleDepositeFromSender]Sender does not exist {}", [event.params.sender.toHex()]);
    return;
  }
  sender.deposit = sender.deposit.plus(event.params.amount);

  let logId = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let senderDepositeLog = SenderDepositeLog.load(logId);
  if (senderDepositeLog) {
    log.error("[handleDepositeFromSender]SenderDepositeLog already exists {}", [logId]);
  } else {
    senderDepositeLog = new SenderDepositeLog(logId);
  }
  senderDepositeLog.sender = sender.id;
  senderDepositeLog.subscription = subscription.id;
  senderDepositeLog.depositeAmount = event.params.amount;
  senderDepositeLog.depositeTime = event.block.timestamp;

  sender.save();
  senderDepositeLog.save();
  subscription.save();  
}

export function handleCancelSubscription(event: CancelSubscription): void {
  let subscription = SubscriptionList.load(event.params.subscriptionId.toHex());
  if (!subscription) {
    log.error("[handleDepositeFromSender]SubscriptionList does not exist {}", [event.params.subscriptionId.toHex()]);
    return;
  }
  subscription.isEntity = false;
  subscription.deposit = subscription.deposit.minus(subscription.remainingBalance);
  subscription.remainingBalance = BigInt.fromI32(0);
  subscription.stopTime = event.block.timestamp;

  let sender = Sender.load(subscription.sender);
  if (!sender) {
    log.error("[handleDepositeFromSender]Sender does not exist {}", [subscription.sender]);
    return;
  }
  sender.deposit = sender.deposit.minus(subscription.remainingBalance);

  sender.save();
  subscription.save();  
}