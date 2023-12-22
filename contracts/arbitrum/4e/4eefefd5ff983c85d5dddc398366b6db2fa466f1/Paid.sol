// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.16;

abstract contract Paid {
    enum PayLock {
        Enabled,
        Disabled
    }

    modifier onlyPaid(uint price) {
        if(msg.value != price) {
            revert IncorrectPayment(msg.value, price);
        } else {
            if(payLock_ == PayLock.Disabled) {
                payLock_ = PayLock.Enabled;
            } else {
                revert ReentryLocked();
            }
        }
        _;
        if(payLock_ == PayLock.Enabled) {
            payLock_ = PayLock.Disabled;
        } else {
            revert ReentryLocked();
        }
    }

    error ReentryLocked();
    error IncorrectPayment(uint paid, uint price);

    PayLock payLock_ = PayLock.Disabled;
}
