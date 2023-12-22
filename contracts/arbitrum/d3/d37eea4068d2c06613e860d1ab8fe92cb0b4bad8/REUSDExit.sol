// SPDX-License-Identifier: reup.cash
pragma solidity ^0.8.19;

import "./UpgradeableBase.sol";
import "./IREUSDExit.sol";
import "./IREStablecoins.sol";
import "./IREUSD.sol";
import "./CheapSafeERC20.sol";

using CheapSafeERC20 for IERC20Full;

/*
    This will hopefully never be deployed

    It's to support a "final exit" contingency plan, where the public
    at large is no longer interested in REUP.  We'll start selling
    properties, directing the proceeds to this contract, which will
    reimburse people 1:1 for their REUSD.
*/
contract REUSDExit is UpgradeableBase(1), IREUSDExit
{
    mapping (uint256 => QueuedExitInfo) queuedExit;
    uint256 public queuedExitStart;
    uint256 public queuedExitEnd;
    uint256 public totalQueued;

    //------------------ end of storage

    bool public constant isREUSDExit = true;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IREUSD immutable REUSD;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IREStablecoins immutable stablecoins;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(IREUSD _reusd, IREStablecoins _stablecoins)
    {
        assert(_reusd.isREUSD() && _stablecoins.isREStablecoins());
        REUSD = _reusd;
        stablecoins = _stablecoins;
    }
    
    function checkUpgradeBase(address newImplementation)
        internal
        override
        view
    {
        assert(IREUSDExit(newImplementation).isREUSDExit());
    }

    function queuedExitAt(uint256 index) external view returns (QueuedExitInfo memory) { return queuedExit[index]; }

    function queueExit(uint256 amount)
        public
    {
        queueExitFor(msg.sender, amount);
    }

    function queueExitFor(address receiver, uint256 amount)
        public
    {
        REUSD.transferFrom(msg.sender, address(this), amount);
        queueExitCore(receiver, amount);
    }

    function queueExitCore(address receiver, uint256 amount)
        private
    {
        if (amount == 0) { revert ZeroAmount(); }
        emit QueueExit(receiver, amount);
        totalQueued += amount;
        uint256 index = queuedExitEnd;
        if (queuedExit[index].user == receiver)
        {
            queuedExit[index].amount += amount;
            return;
        }
        if (queuedExit[index].amount > 0)
        {
            ++index;
            ++queuedExitEnd;
        }
        queuedExit[index] = QueuedExitInfo({
            user: receiver,
            amount: amount
        });
    }

    function queueExitPermit(uint256 amount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        REUSD.permit(msg.sender, address(this), permitAmount, deadline, v, r, s);
        queueExit(amount);
    }

    function fund(IERC20Full token, uint256 maxTokenAmount)
        public
    {
        if (maxTokenAmount == 0) { revert ZeroAmount(); }
        uint256 factor = stablecoins.getMultiplyFactor(token);
        uint256 maxREUSDAmount = maxTokenAmount * factor;
        uint256 index = queuedExitStart;
        uint256 end = queuedExitEnd;
        uint256 total = 0;
        while (true)
        {
            QueuedExitInfo memory info = queuedExit[index];
            uint256 reusdAmount = info.amount > maxREUSDAmount ? maxREUSDAmount : info.amount;
            if (reusdAmount > 0)
            {
                token.safeTransferFrom(msg.sender, info.user, reusdAmount / factor);
                maxREUSDAmount -= reusdAmount;
                emit Exit(info.user, reusdAmount);
                total += reusdAmount;
                info.amount -= reusdAmount;
            }
            if (info.amount > 0)
            {
                queuedExit[index].amount = info.amount;
            }
            else
            {
                delete queuedExit[index];
            }
            if (index < end && info.amount == 0)
            {
                queuedExitStart = ++index;
            }
            else if (index == end || info.amount > 0)
            {
                totalQueued -= total;
                REUSD.transfer(address(0), total);
                return;
            }            
        }
    }

    function fundPermit(IERC20Full token, uint256 maxTokenAmount, uint256 permitAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
    {
        token.permit(msg.sender, address(this), permitAmount, deadline, v, r, s);
        fund(token, maxTokenAmount);
    }
}
