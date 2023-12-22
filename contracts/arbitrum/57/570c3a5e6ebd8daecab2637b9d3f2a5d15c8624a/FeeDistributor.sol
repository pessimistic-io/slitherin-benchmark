// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./Math.sol";

import "./IFeeDistributor.sol";
import "./IERC20.sol";
import "./IVoter.sol";
import "./IVotingEscrow.sol";

contract FeeDistributor is Initializable, IFeeDistributor {
    uint256 public constant WEEK = 1 weeks;

    address public voter; // only voter can modify balances (since it only happens on vote())
    address public _ve;
    uint256 internal _unlocked;

    // period => token => total supply
    mapping(uint256 => mapping(address => uint256))
        public tokenTotalSupplyByPeriod;

    // token id => amount
    mapping(uint256 => uint256) public balanceOf;

    // period => token id => amount
    mapping(uint256 => mapping(uint256 => uint256)) public veShareByPeriod;

    // period => amount
    mapping(uint256 => uint256) public totalVeShareByPeriod;

    // period => token id => token => amount
    mapping(uint256 => mapping(uint256 => mapping(address => uint256)))
        public veWithdrawnTokenAmountByPeriod;

    uint256 public firstPeriod;

    // token => token id => period
    mapping(address => mapping(uint256 => uint256)) public lastClaimByToken;

    address[] public rewards;
    mapping(address => bool) public isReward;

    event Deposit(address indexed from, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 tokenId, uint256 amount);
    event NotifyReward(
        address indexed from,
        address indexed reward,
        uint256 amount,
        uint256 period
    );
    event Bribe(
        address indexed from,
        address indexed reward,
        uint256 amount,
        uint256 period
    );
    event ClaimRewards(
        uint256 period,
        uint256 tokenId,
        address receiver,
        address reward,
        uint256 amount
    );

    function initialize(address _voter) public initializer {
        _unlocked = 1;

        voter = _voter;
        _ve = IVoter(_voter)._ve();

        firstPeriod = getPeriod();
    }

    // simple re-entrancy check
    modifier lock() {
        require(_unlocked == 1, "locked");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewards;
    }

    function _getReward(
        uint256 period,
        uint256 tokenId,
        address token,
        address receiver
    ) internal {
        if (totalVeShareByPeriod[period] != 0) {
            uint256 _reward = (tokenTotalSupplyByPeriod[period][token] *
                veShareByPeriod[period][tokenId]) /
                totalVeShareByPeriod[period];

            _reward -= veWithdrawnTokenAmountByPeriod[period][tokenId][token];
            veWithdrawnTokenAmountByPeriod[period][tokenId][token] += _reward;

            if (_reward > 0) {
                _safeTransfer(token, receiver, _reward);
                emit ClaimRewards(period, tokenId, receiver, token, _reward);
            }
        }
    }

    function _getAllRewards(
        uint256 tokenId,
        address[] memory tokens,
        address receiver
    ) internal {
        uint256 currentPeriod = getPeriod();
        uint256 lastClaim;
        for (uint256 i = 0; i < tokens.length; ++i) {
            lastClaim = Math.max(
                lastClaimByToken[tokens[i]][tokenId],
                firstPeriod
            );
            for (
                uint256 period = lastClaim;
                period <= currentPeriod;
                period += WEEK
            ) {
                _getReward(period, tokenId, tokens[i], receiver);
            }
            lastClaimByToken[tokens[i]][tokenId] = currentPeriod - WEEK;
        }
    }

    function getPeriodReward(
        uint256 period,
        uint256 tokenId,
        address token
    ) external lock {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, tokenId));
        _getReward(period, tokenId, token, msg.sender);
    }

    function getReward(uint256 tokenId, address[] memory tokens) external lock {
        require(IVotingEscrow(_ve).isApprovedOrOwner(msg.sender, tokenId));
        _getAllRewards(tokenId, tokens, msg.sender);
    }

    // used by Voter to allow batched reward claims
    function getRewardForOwner(
        uint256 tokenId,
        address[] memory tokens
    ) external lock {
        require(msg.sender == voter);
        address owner = IVotingEscrow(_ve).ownerOf(tokenId);
        _getAllRewards(tokenId, tokens, owner);
    }

    function earned(
        address token,
        uint256 tokenId
    ) external view returns (uint256 reward) {
        uint256 currentPeriod = getPeriod();
        uint256 lastClaim = Math.max(
            lastClaimByToken[token][tokenId],
            firstPeriod
        );
        for (
            uint256 period = lastClaim;
            period <= currentPeriod;
            period += WEEK
        ) {
            if (totalVeShareByPeriod[period] != 0) {
                reward +=
                    (tokenTotalSupplyByPeriod[period][token] *
                        veShareByPeriod[period][tokenId]) /
                    totalVeShareByPeriod[period];

                reward -= veWithdrawnTokenAmountByPeriod[period][tokenId][
                    token
                ];
            }
        }
    }

    function getPeriod() public view returns (uint256) {
        return (block.timestamp / WEEK) * WEEK;
    }

    // This is an external function, but internal notation is used since it can only be called "internally" from Voter
    function _deposit(uint256 amount, uint256 tokenId) external {
        require(msg.sender == voter);

        uint256 period = getPeriod() + WEEK;

        balanceOf[tokenId] += amount;
        totalVeShareByPeriod[period] += amount;
        veShareByPeriod[period][tokenId] += amount;

        emit Deposit(msg.sender, tokenId, amount);
    }

    function _withdraw(uint256 amount, uint256 tokenId) external {
        require(msg.sender == voter);

        uint256 period = getPeriod() + WEEK;

        balanceOf[tokenId] -= amount;
        if (veShareByPeriod[period][tokenId] > 0) {
            veShareByPeriod[period][tokenId] -= amount;
            totalVeShareByPeriod[period] -= amount;
        }

        emit Withdraw(msg.sender, tokenId, amount);
    }

    function notifyRewardAmount(address token, uint256 amount) external lock {
        uint256 period = getPeriod();

        // there is no votes for first period, so distribute first period fees to second period voters
        if (totalVeShareByPeriod[period] == 0) {
            period += WEEK;
        }

        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        uint balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;
        tokenTotalSupplyByPeriod[period][token] += amount;
        emit NotifyReward(msg.sender, token, amount, period);
    }

    // record bribe amount for next period
    function bribe(address token, uint256 amount) external lock {
        uint256 period = getPeriod() + WEEK;

        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
        }

        uint balanceBefore = IERC20(token).balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint balanceAfter = IERC20(token).balanceOf(address(this));

        amount = balanceAfter - balanceBefore;
        tokenTotalSupplyByPeriod[period][token] += amount;
        emit Bribe(msg.sender, token, amount, period);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

