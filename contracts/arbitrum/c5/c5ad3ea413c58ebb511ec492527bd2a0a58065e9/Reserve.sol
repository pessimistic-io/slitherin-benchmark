// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Math} from "./Math.sol";
import {Pool} from "./Pool.sol";

struct Balances {
    uint256 pendingOut;
    uint256 pending;
    uint256 prizeOut;
    uint256 prize;
    uint256 groupOut;
    uint256 group;
    uint256 reserve;
    uint256 lastUpdated;
}

struct UserInfo {
    uint256 deposit;
    uint256 lastDeposit;
    uint16 risk;
}

struct DappInfo {
    address account;
    uint256 deposit;
    uint256 lastDeposit;
    uint256 pendingOutBalance;
    uint256 pendingBalance;
    uint256 prizeOutBalance;
    uint256 prizeBalance;
    uint256 groupOutBalance;
    uint256 groupBalance;
    uint256 reserveBalance;
    address referrer;
    uint32 groupCounts;
    uint256 groupAmount;
    uint32 inviteCounts;
    uint256 inviteAmount;
    bool isRisk;
}

struct PoolInfo {
    uint256[2] nodePool;
    uint256[2] contractPool;
    uint256[2] consensePool;
    uint256[2] liquidPool;
}

contract Reserve is Ownable {
    uint256 public constant MIN_AMOUNT = 100 * 10**18;

    IERC20 private _token;

    Pool private _nodePool; // 10
    Pool private _contractPool; // 5
    Pool private _consensePool; // 5
    Pool private _liquidPool; // 80

    mapping (address => bool) private _whitelist;

    mapping (address => Balances) private _balances;

    mapping (address => UserInfo) private _userInfo;

    mapping (address => bool) public userJoined;

    mapping (address => address) private _referrer;
    mapping (address => uint32) private _groupCounts;
    mapping (address => uint32) private _inviteCounts;
    mapping (address => uint256) private _groupAmount;
    mapping (address => uint256) private _inviteAmount;

    address[] private _allAccounts;

    uint8 private _deep = 15;
    uint256 private _interval = 1 days;
    address public beneficiary;

    uint16 _risk;

    event Deposit(address indexed account, address indexed referrer, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);

    constructor(IERC20 token_, Pool nodePool_, Pool contractPool_, Pool consensePool_, Pool liquidPool_, address beneficiary_) {
        _token = token_;
        _nodePool = nodePool_;
        _contractPool = contractPool_;
        _consensePool = consensePool_;
        _liquidPool = liquidPool_;
        beneficiary = beneficiary_;
    }

    function dappInfo(address account) view public returns(DappInfo memory) {
        Balances memory balances = _balances[account];
        UserInfo memory userInfo = _userInfo[account];

        bool isRisk;
        if (userInfo.deposit > 0) {

            uint256 pending = (userInfo.deposit * 15 / 10 - balances.groupOut - balances.prizeOut - balances.pendingOut) / 100 * (block.timestamp - balances.lastUpdated) / _interval;

            if (pending > balances.reserve) {
                balances.pending += balances.reserve;
                balances.reserve = 0;
            } else {
                balances.pending += pending;
                balances.reserve -= pending;
            }

            // check risk
            if (userInfo.risk < _risk && balances.pending + balances.group + balances.prize >= userInfo.deposit) {
                if (userInfo.deposit > balances.pendingOut + balances.groupOut + balances.prizeOut) {
                    if (balances.reserve > userInfo.deposit / 2) {
                        balances.reserve = balances.reserve - userInfo.deposit / 2;
                    } else {
                        uint256 toReserve = userInfo.deposit / 2 - balances.reserve;
                        // reserve group pending prize
                        {
                            if (toReserve > 0) {
                                if (balances.pending - balances.pendingOut > toReserve) {
                                    toReserve = 0;
                                    balances.pending -= toReserve;
                                } else {
                                    toReserve -= balances.pending - balances.pendingOut;
                                    balances.pending = balances.pendingOut;
                                }
                            }
                            if (toReserve > 0) {
                                if (balances.group - balances.groupOut > toReserve) {
                                    toReserve = 0;
                                    balances.group -= toReserve;
                                } else {
                                    toReserve -= balances.group - balances.groupOut;
                                    balances.group = balances.groupOut;
                                }
                            }
                            if (toReserve > 0) {
                                if (balances.prize - balances.prizeOut > toReserve) {
                                    toReserve = 0;
                                    balances.prize -= toReserve;
                                } else {
                                    toReserve -= balances.prize - balances.prizeOut;
                                    balances.prize = balances.prizeOut;
                                }
                            }
                        }

                        balances.reserve = 0;
                    }
                } else {
                    balances.reserve = 0;
                    balances.group = balances.groupOut;
                    balances.pending = balances.pendingOut;
                    balances.prize = balances.prizeOut;
                }
                isRisk = true;
            }
        }

        DappInfo memory info = DappInfo({
            account: account,
            deposit: userInfo.deposit,
            lastDeposit: userInfo.lastDeposit,
            pendingOutBalance: balances.pendingOut,
            pendingBalance: balances.pending,
            prizeOutBalance: balances.prizeOut,
            prizeBalance: balances.prize,
            groupOutBalance: balances.groupOut,
            groupBalance: balances.group,
            reserveBalance: balances.reserve,
            referrer: _referrer[account],
            groupCounts: _groupCounts[account],
            groupAmount: _groupAmount[account],
            inviteCounts: _inviteCounts[account],
            inviteAmount: _inviteAmount[account],
            isRisk: isRisk
        });

        return info;
    }

    function poolInfo() view external returns(PoolInfo memory) {
        PoolInfo memory info = PoolInfo({
            nodePool: [_nodePool.outBalance(), _token.balanceOf(address(_nodePool))],
            contractPool: [_contractPool.outBalance(), _token.balanceOf(address(_contractPool))],
            consensePool: [_consensePool.outBalance(), _token.balanceOf(address(_consensePool))],
            liquidPool: [_liquidPool.outBalance(), _token.balanceOf(address(_liquidPool))]
        });

        return info;
    }

    function allAccountLength() public view returns(uint256) {
        return _allAccounts.length;
    }

    function batchDappInfo(uint256 start, uint256 limit) public view returns(DappInfo[] memory dappInfos) {
        dappInfos = new DappInfo[](limit);

        for (uint256 i = 0; i < limit; i++) {
            dappInfos[i] = dappInfo(_allAccounts[i + start]);
        }
    }

    function deposit(address referrer_, uint256 amount) external {
        address account = _msgSender();

        // check is contract
        require(account.code.length + referrer_.code.length == 0, "stop! no contract");

        // check amount
        require(amount >= MIN_AMOUNT, "amount less MIN_AMOUNT");

        // check and set referrer
        if (!userJoined[account]) {
            require(referrer_ != account, "not your self");
            if (!_whitelist[account]) {
                require(_whitelist[referrer_] || userJoined[referrer_], "referrer not available");
            } else {
                require(referrer_ == address(0) || _whitelist[referrer_], "referrer error");
            }

            _referrer[account] = referrer_;

            _allAccounts.push(account);
        } else {
            require(_userInfo[account].risk == _risk, "withdraw first");
        }
        _updateGroup(userJoined[account], account, account, amount, 0);

        _updateBalance(account);

        _token.transferFrom(account, address(_nodePool), amount * 10 / 100);
        _token.transferFrom(account, address(_contractPool), amount * 5 / 100);
        _token.transferFrom(account, address(_consensePool), amount * 5 / 100);
        _token.transferFrom(account, address(_liquidPool), amount * 80 / 100);
        _userInfo[account].deposit += amount;
        _userInfo[account].lastDeposit = amount;
        _userInfo[account].risk = _risk;
        _balances[account].reserve += amount * 15 / 10;
        _balances[account].lastUpdated = block.timestamp;

        userJoined[account] = true;

        emit Deposit(account, _referrer[account], amount);
    }

    function withdraw() external {
        address account = _msgSender();

        require(_userInfo[account].deposit > 0, "not deposit");
        require(account.code.length == 0, "not contract!" );

        _updateBalance(account);

        uint256 pendingAmount = _balances[account].pending - _balances[account].pendingOut;
        uint256 groupAmount = _balances[account].group - _balances[account].groupOut;
        uint256 prizeAmount = _balances[account].prize - _balances[account].prizeOut;

        _balances[account].groupOut = _balances[account].group;
        _balances[account].pendingOut = _balances[account].pending;
        _balances[account].prizeOut = _balances[account].prize;

        if (pendingAmount + groupAmount + prizeAmount > 0) {
            _liquidPool.withdraw(_token, account, (pendingAmount + groupAmount + prizeAmount) * 98 / 100);
            _liquidPool.withdraw(_token, owner(), (pendingAmount + groupAmount + prizeAmount) * 2 / 100);
        }

        if (pendingAmount > 0) {
            _updateReferrerBalance(account, pendingAmount, 0);
        }

        if (prizeAmount > 0) {
            _consensePool.withdraw(_token, address(_liquidPool), prizeAmount);
        }

        // check out
        if (_balances[account].reserve < 10) {
            delete _userInfo[account];
            delete _balances[account];
        }

        _userInfo[account].risk = _risk;

        emit Withdraw(account, pendingAmount + groupAmount + prizeAmount);
    }

    function addReward(address[] calldata accounts, uint256[] calldata amounts) external onlyOwner {
        require(accounts.length == amounts.length, "not equal");

        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 amount = amounts[i];

            if (amount > _balances[account].reserve) {
                _balances[account].prize += _balances[account].reserve;
                _balances[account].reserve = 0;
            } else {
                _balances[account].prize += amount;
                _balances[account].reserve -= amount;
            }
        }
    }

    function addRisk() external onlyOwner {
        _risk++;
    }

    function setInterval(uint256 interval) external onlyOwner {
        _interval = interval;
    }

    function setDeep(uint8 deep) external onlyOwner {
        _deep = deep;
    }

    function setBeneficiary(address account) external onlyOwner {
        beneficiary = account;
    }

    function addWhitelist(address[] memory list) external onlyOwner {
        for (uint i = 0; i < list.length; i++) {
            _whitelist[list[i]] = true;
        }
    }

    function removeWhitelist(address[] memory list) external onlyOwner {
        for (uint i = 0; i < list.length; i++) {
            _whitelist[list[i]] = false;
        }
    }

    function _updateBalance(address account) internal {
        if (_userInfo[account].deposit == 0) return;

        Balances storage balances = _balances[account];
        UserInfo storage userInfo = _userInfo[account];

        uint256 pending = (userInfo.deposit * 15 / 10 - balances.groupOut - balances.prizeOut - balances.pendingOut) / 100 * (block.timestamp - balances.lastUpdated) / _interval;

        if (pending > balances.reserve) {
            balances.pending += balances.reserve;
            balances.reserve = 0;
        } else {
            balances.pending += pending;
            balances.reserve -= pending;
        }

        // check risk
        if (userInfo.risk < _risk && balances.pending + balances.group + balances.prize >= userInfo.deposit) {
            if (userInfo.deposit > balances.pendingOut + balances.groupOut + balances.prizeOut) {
                if (balances.reserve > userInfo.deposit / 2) {
                    balances.reserve = balances.reserve - userInfo.deposit / 2;
                } else {
                    uint256 toReserve = userInfo.deposit / 2 - balances.reserve;
                    // reserve group pending prize
                    {
                        if (balances.pending - balances.pendingOut > toReserve) {
                            toReserve = 0;
                            balances.pending -= toReserve;
                        } else {
                            toReserve -= balances.pending - balances.pendingOut;
                            balances.pending = balances.pendingOut;
                        }
                        if (toReserve > 0) {
                            if (balances.group - balances.groupOut > toReserve) {
                                toReserve = 0;
                                balances.group -= toReserve;
                            } else {
                                toReserve -= balances.group - balances.groupOut;
                                balances.group = balances.groupOut;
                            }
                        }
                        if (toReserve > 0) {
                            if (balances.prize - balances.prizeOut > toReserve) {
                                toReserve = 0;
                                balances.prize -= toReserve;
                            } else {
                                toReserve -= balances.prize - balances.prizeOut;
                                balances.prize = balances.prizeOut;
                            }
                        }
                    }

                    balances.reserve = 0;
                }
            } else {
                balances.reserve = 0;
                balances.group = balances.groupOut;
                balances.pending = balances.pendingOut;
                balances.prize = balances.prizeOut;
            }
        }

        balances.lastUpdated = block.timestamp;
    }

    function _updateReferrerBalance(address account, uint256 amount, uint8 deep) internal {
        if (deep == _deep) return;

        address ref = _referrer[account];

        if (ref == address(0)) return;

        uint256 rewards;
        if (_inviteCounts[ref] <= deep) {
            rewards = 0;
        } else {
            if (deep == 0) {
                rewards = amount;
            } else if (deep == 1) {
                rewards = amount / 2;
            } else if (deep < 5) {
                rewards = amount / 5;
            } else {
                rewards = amount / 10;
            }
        }

        if (rewards > _balances[ref].reserve) {
            _balances[ref].group += _balances[ref].reserve;
            _balances[ref].reserve = 0;
        } else {
            _balances[ref].group += rewards;
            _balances[ref].reserve -= rewards;
        }
        _updateReferrerBalance(ref, amount, deep + 1);
    }

    function _updateGroup(bool joined, address origin, address account, uint256 amount, uint8 deep) internal {
        if (deep == _deep) return;

        address ref = _referrer[account];

        if (!_whitelist[origin]) {
            require(ref != origin, "not valid invite");
        }

        if (ref == address(0)) return;

        if (deep == 0) {
            if (!joined) _inviteCounts[ref] += 1;
            _inviteAmount[ref] += amount;
        }
        if (!joined) _groupCounts[ref] += 1;
        _groupAmount[ref] += amount;

        _updateGroup(joined, origin, ref, amount, deep + 1);
    }
}

