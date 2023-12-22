// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.19;

import "./Initializable.sol";
import "./ERC20_IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable2Step.sol";
import "./Math.sol";
import "./ReentrancyGuard.sol";

import "./IPresale.sol";
import "./IPresaleErrors.sol";

/**
 * @notice Implementation of the {IPresale} interface.
 */
contract Presale is IPresale, IPresaleErrors, Ownable2Step, Initializable, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable override PRESALE_ASSET;
    IERC20 public immutable override PRESALE_TOKEN;
    uint256 public immutable override PRECISION = 1e8;

    uint256 private $currentRoundIndex;
    uint256 private $totalRaised;
    uint256 private $totalPurchases;
    address private $withdrawTo;

    bool private $closed;

    PresaleConfig private $config;
    RoundConfig[] private $rounds;

    mapping(uint256 => uint256) private $roundTokensAllocated;
    mapping(address => uint256) private $userTokensAllocated;

    constructor(IERC20 presaleAsset, IERC20 presaleToken, address newOwner) {
        if (!Address.isContract(address(presaleAsset))) {
            revert PresaleInvalidContract(address(presaleAsset));
        }

        if (!Address.isContract(address(presaleToken))) {
            revert PresaleInvalidContract(address(presaleToken));
        }

        PRESALE_ASSET = presaleAsset;
        PRESALE_TOKEN = presaleToken;

        _transferOwnership(newOwner);
    }

    /**
     * @inheritdoc IPresale
     */
    function initialize(address newWithdrawTo, PresaleConfig memory newConfig, RoundConfig[] memory newRounds)
        external
        override
        onlyOwner
        initializer
    {
        _setWithdrawTo(newWithdrawTo);
        _setConfig(newConfig);
        _setRounds(newRounds);
    }

    /**
     * @inheritdoc IPresale
     */
    function close() external override onlyOwner {
        _close();
    }

    /**
     * @inheritdoc IPresale
     */
    function setWithdrawTo(address newWithdrawTo) external override onlyOwner {
        _setWithdrawTo(newWithdrawTo);
    }

    /**
     * @inheritdoc IPresale
     */
    function purchase(address account, uint256 assetAmount)
        external
        override
        nonReentrant
        returns (Receipt memory receipt)
    {
        if (account == address(0)) {
            revert PresaleInvalidAddress(account);
        }

        PresaleConfig memory _config = $config;

        if (block.timestamp < _config.startDate) {
            revert PresaleInvalidState(PresaleState.NOT_STARTED);
        }

        if (assetAmount == 0 || assetAmount < _config.minDepositAmount) {
            revert PresaleInsufficientAmount(assetAmount, _config.minDepositAmount == 0 ? 1 : _config.minDepositAmount);
        }

        if ($closed) {
            revert PresaleInvalidState(PresaleState.CLOSED);
        }

        receipt.id = ++$totalPurchases;

        PurchaseCache memory _c;
        _c.totalRounds = $rounds.length;
        _c.currentIndex = $currentRoundIndex;
        _c.remainingAssets = assetAmount;
        _c.userAllocationRemaining = _config.maxUserAllocation - $userTokensAllocated[account];

        while (_c.currentIndex < _c.totalRounds && _c.remainingAssets > 0 && _c.userAllocationRemaining > 0) {
            RoundConfig memory _round = $rounds[_c.currentIndex];

            _c.roundAllocationRemaining = _remainingRoundAllocation(_c.currentIndex, _round);
            _c.userAllocation = assetsToTokens(_c.remainingAssets, _round.price);

            if (_c.userAllocation > _c.roundAllocationRemaining) {
                _c.userAllocation = _c.roundAllocationRemaining;
            }
            if (_c.userAllocation > _c.userAllocationRemaining) {
                _c.userAllocation = _c.userAllocationRemaining;
            }

            if (_c.userAllocation > 0) {
                uint256 _costAssets = tokensToAssets(_c.userAllocation, _round.price);

                _c.remainingAssets = _subZero(_c.remainingAssets, _costAssets);
                _c.userAllocationRemaining = _subZero(_c.userAllocationRemaining, _c.userAllocation);
                _c.totalTokenAllocation += _c.userAllocation;

                $roundTokensAllocated[_c.currentIndex] += _c.userAllocation;

                emit Purchase(receipt.id, _c.currentIndex, account, _costAssets, _c.userAllocation);
            }

            // if we have used everything then lets increment current index. and only increment if we are not on the last round.
            if (_c.userAllocation == _c.roundAllocationRemaining && _c.currentIndex < _c.totalRounds - 1) {
                _c.currentIndex++;
            } else {
                break;
            }
        }

        receipt.refundedAssets = _c.remainingAssets;
        receipt.tokensAllocated = _c.totalTokenAllocation;
        receipt.costAssets = assetAmount - receipt.refundedAssets;

        unchecked {
            $totalRaised += receipt.costAssets;
            $currentRoundIndex = _c.currentIndex;
            $userTokensAllocated[account] = _config.maxUserAllocation - _c.userAllocationRemaining;
        }

        if (receipt.tokensAllocated == 0) {
            revert PresaleInsufficientAllocation(receipt.tokensAllocated, 1);
        }

        if (receipt.refundedAssets > 0) {
            _sendAssets(account, receipt.refundedAssets);
        }

        if (receipt.costAssets > 0) {
            _sendAssets($withdrawTo, receipt.costAssets);
        }

        PRESALE_TOKEN.safeTransfer(account, receipt.tokensAllocated);

        // if all the tokens have been purchased then close the presale
        if (_c.roundAllocationRemaining == _c.userAllocation && _c.currentIndex == _c.totalRounds - 1) {
            _close();
        }

        emit PurchaseReceipt(receipt.id, account, assetAmount, receipt, _msgSender());
    }

    /**
     * @inheritdoc IPresale
     */
    function withdrawTo() external view override returns (address) {
        return $withdrawTo;
    }

    /**
     * @inheritdoc IPresale
     */
    function currentRoundIndex() external view override returns (uint256) {
        return $currentRoundIndex;
    }

    /**
     * @inheritdoc IPresale
     */
    function config() external view override returns (PresaleConfig memory) {
        return $config;
    }

    /**
     * @inheritdoc IPresale
     */
    function closed() external view override returns (bool) {
        return $closed;
    }

    /**
     * @inheritdoc IPresale
     */
    function round(uint256 roundIndex) external view override returns (RoundConfig memory) {
        return $rounds[roundIndex];
    }

    /**
     * @inheritdoc IPresale
     */
    function rounds() external view override returns (RoundConfig[] memory) {
        return $rounds;
    }

    /**
     * @inheritdoc IPresale
     */
    function totalPurchases() external view override returns (uint256) {
        return $totalPurchases;
    }

    /**
     * @inheritdoc IPresale
     */
    function totalRounds() external view override returns (uint256) {
        return $rounds.length;
    }

    /**
     * @inheritdoc IPresale
     */
    function totalRaised() external view override returns (uint256) {
        return $totalRaised;
    }

    /**
     * @inheritdoc IPresale
     */
    function roundTokensAllocated(uint256 roundIndex) external view returns (uint256) {
        return $roundTokensAllocated[roundIndex];
    }

    /**
     * @inheritdoc IPresale
     */
    function userTokensAllocated(address account) external view override returns (uint256) {
        return $userTokensAllocated[account];
    }

    /**
     * @inheritdoc IPresale
     */
    function assetsToTokens(uint256 amount, uint256 price) public pure override returns (uint256) {
        return (amount * PRECISION) / price;
    }

    /**
     * @inheritdoc IPresale
     */
    function tokensToAssets(uint256 amount, uint256 price) public pure override returns (uint256) {
        return (amount * price).ceilDiv(PRECISION);
    }

    /**
     * @dev ends the presale early preventing any further purchasing of tokens. This will also return any remaining
     * PRESALE_TOKENs to the withdrawTo address.
     */
    function _close() private {
        if ($closed) {
            revert PresaleInvalidState(PresaleState.CLOSED);
        }

        $closed = true;

        uint256 _remainingBalance = PRESALE_TOKEN.balanceOf(address(this));
        if (_remainingBalance > 0) {
            PRESALE_TOKEN.safeTransfer($withdrawTo, _remainingBalance);
        }

        emit Close();
    }

    /**
     * @dev sets the rounds for the presale. This will determine the price and allocation for each round.
     * @param newRounds the new rounds to set
     */
    function _setRounds(RoundConfig[] memory newRounds) internal {
        if (newRounds.length == 0) {
            revert PresaleInsufficientRounds();
        }

        uint256 _totalTokenAllocation;
        for (uint256 i; i < newRounds.length; ++i) {
            $rounds.push(newRounds[i]);
            _totalTokenAllocation += newRounds[i].allocation;
        }

        delete $currentRoundIndex;

        PRESALE_TOKEN.safeTransferFrom(_msgSender(), address(this), _totalTokenAllocation);

        emit RoundsUpdate(newRounds, _msgSender());
    }

    /**
     * @dev sets the presale configuration values
     * @param newConfig the config to set
     */
    function _setConfig(PresaleConfig memory newConfig) internal {
        if (newConfig.startDate <= block.timestamp) {
            revert PresaleInvalidStartDate(newConfig.startDate, block.timestamp);
        }

        if (newConfig.maxUserAllocation == 0) {
            revert PresaleInsufficientMaxUserAllocation(newConfig.maxUserAllocation, 1);
        }

        emit ConfigUpdate(newConfig, _msgSender());
        $config = newConfig;
    }

    /**
     * @dev Sets the withdrawTo for the contract. This address will be where the PRESALE_ASSETs are sent.
     * @param newWithdrawTo the new address to send to
     */
    function _setWithdrawTo(address newWithdrawTo) internal {
        if (newWithdrawTo == address(0) || newWithdrawTo == $withdrawTo) {
            revert PresaleInvalidAddress(newWithdrawTo);
        }

        emit WithdrawToUpdate(newWithdrawTo, _msgSender());
        $withdrawTo = newWithdrawTo;
    }

    /**
     * @dev sends the PRESALE_ASSETs to a designated account and amount. It will not do any transfer if the sender
     * and the receiver are the same address
     * @param account the account to transfer to
     * @param amount the amount of assets to send
     */
    function _sendAssets(address account, uint256 amount) private {
        address _sender = _msgSender();
        if (_sender != account) {
            PRESALE_ASSET.safeTransferFrom(_sender, account, amount);
        }
    }

    /**
     * @dev Calculates the rounds remaining allocation
     * @param roundIndex the round index to query
     * @param round_ the {RoundConfig} which is associated to the roundIndex
     */
    function _remainingRoundAllocation(uint256 roundIndex, RoundConfig memory round_) private view returns (uint256) {
        uint256 _roundTotalAllocated = $roundTokensAllocated[roundIndex];
        return _subZero(round_.allocation, _roundTotalAllocated);
    }

    /**
     * @dev attempts to subtract b from a. If it would be negative then return 0 otherwise return the value.
     * @param a the value being subtracted from
     * @param b the value being subtracted
     */
    function _subZero(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            return a > b ? a - b : 0;
        }
    }
}

