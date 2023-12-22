// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./IterableMapping.sol";

pragma solidity ^0.8.4;

contract SharesDist is Ownable, Pausable {
    using SafeMath for uint256;
    using IterableMapping for IterableMapping.Map;

    struct ShareEntity {
        uint creationTime;
        uint lastClaimTime;
        uint256 amount;
    }

    IterableMapping.Map private shareOwners;
    mapping(address => ShareEntity[]) private _sharesOfUser;

    address public token;
    uint8 public rewardPerShare;
    uint256 public minPrice;

    uint256 public totalSharesCreated = 0;
    uint256 public totalStaked = 0;
    uint256 public totalClaimed = 0;

    uint8[] private _boostMultipliers = [105, 120, 140];
    uint8[] private _boostRequiredDays = [3, 7, 15];

    event ShareCreated(
        uint256 indexed amount,
        address indexed account,
        uint indexed blockTime
    );

    modifier onlyGuard() {
        require(owner() == _msgSender() || token == _msgSender(), "NOT_GUARD");
        _;
    }

    modifier onlyShareOwner(address account) {
        require(isShareOwner(account), "NOT_OWNER");
        _;
    }

    constructor(
        uint8 _rewardPerShare,
        uint256 _minPrice
    ) {
        rewardPerShare = _rewardPerShare;
        minPrice = _minPrice;
    }

    // Private methods


    function _getShareWithCreatime(
        ShareEntity[] storage shares,
        uint256 _creationTime
    ) private view returns (ShareEntity storage) {
        uint256 numberOfShares = shares.length;
        require(
            numberOfShares > 0,
            "CASHOUT ERROR: You don't have shares to cash-out"
        );
        bool found = false;
        int256 index = _binarySearch(shares, 0, numberOfShares, _creationTime);
        uint256 validIndex;
        if (index >= 0) {
            found = true;
            validIndex = uint256(index);
        }
        require(found, "share SEARCH: No share Found with this blocktime");
        return shares[validIndex];
    }

    function _binarySearch(
        ShareEntity[] memory arr,
        uint256 low,
        uint256 high,
        uint256 x
    ) private view returns (int256) {
        if (high >= low) {
            uint256 mid = (high + low).div(2);
            if (arr[mid].creationTime == x) {
                return int256(mid);
            } else if (arr[mid].creationTime > x) {
                return _binarySearch(arr, low, mid - 1, x);
            } else {
                return _binarySearch(arr, mid + 1, high, x);
            }
        } else {
            return -1;
        }
    }

    function _uint2str(uint256 _i)
        private
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _calculateShareRewards(uint _lastClaimTime, uint256 amount_) private view returns (uint256 rewards) {
        uint256 elapsedTime_ = (block.timestamp - _lastClaimTime);
        uint256 boostMultiplier = _calculateBoost(elapsedTime_).div(100);
        uint256 rewardPerDay = amount_.mul(rewardPerShare).div(100);
        return ((rewardPerDay.mul(10000).div(1440) * (elapsedTime_ / 1 minutes)) / 10000) * boostMultiplier;
    }

    function _calculateBoost(uint elapsedTime_) internal view returns (uint256) {
        uint256 elapsedTimeInDays_ = elapsedTime_ / 1 days;

        if (elapsedTimeInDays_ >= _boostRequiredDays[2]) {
            return _boostMultipliers[2];
        } else if (elapsedTimeInDays_ >= _boostRequiredDays[1]) {
            return _boostMultipliers[1];
        } else if (elapsedTimeInDays_ >= _boostRequiredDays[0]) {
            return _boostMultipliers[0];
        } else {
            return 100;
        }
    }

    // External methods

    function createShare(address account,uint256 amount_) external onlyGuard whenNotPaused {
        ShareEntity[] storage _shares = _sharesOfUser[account];
        require(_shares.length <= 100, "Max shares exceeded");
        _shares.push(
            ShareEntity({
                creationTime: block.timestamp,
                lastClaimTime: block.timestamp,
                amount: amount_
            })
        );
        shareOwners.set(account, _sharesOfUser[account].length);
        emit ShareCreated(amount_, account, block.timestamp);
        totalSharesCreated++;
        totalStaked += amount_;
    }

    function getShareReward(address account, uint256 _creationTime)
        external
        view
        returns (uint256)
    {
        require(_creationTime > 0, "share: CREATIME must be higher than zero");
        ShareEntity[] storage shares = _sharesOfUser[account];
        require(
            shares.length > 0,
            "CASHOUT ERROR: You don't have shares to cash-out"
        );
        ShareEntity storage share = _getShareWithCreatime(shares, _creationTime);
        return _calculateShareRewards(share.lastClaimTime, share.amount);
    }

    function getAllSharesRewards(address account)
        external
        view
        returns (uint256)
    {
        ShareEntity[] storage shares = _sharesOfUser[account];
        uint256 sharesCount = shares.length;
        require(sharesCount > 0, "share: CREATIME must be higher than zero");
        ShareEntity storage _share;
        uint256 rewardsTotal = 0;
        for (uint256 i = 0; i < sharesCount; i++) {
            _share = shares[i];
            rewardsTotal += _calculateShareRewards(_share.lastClaimTime, _share.amount);
        }
        return rewardsTotal;
    }

    function cashoutShareReward(address account, uint256 _creationTime)
        external
        onlyGuard
        onlyShareOwner(account)
        whenNotPaused
    {
        require(_creationTime > 0, "share: CREATIME must be higher than zero");
        ShareEntity[] storage shares = _sharesOfUser[account];
        require(
            shares.length > 0,
            "CASHOUT ERROR: You don't have shares to cash-out"
        );
        ShareEntity storage share = _getShareWithCreatime(shares, _creationTime);
        share.lastClaimTime = block.timestamp;
    }

    function compoundShareReward(address account, uint256 _creationTime, uint256 rewardAmount_)
        external
        onlyGuard
        onlyShareOwner(account)
        whenNotPaused
    {
        require(_creationTime > 0, "share: CREATIME must be higher than zero");
        ShareEntity[] storage shares = _sharesOfUser[account];
        require(
            shares.length > 0,
            "CASHOUT ERROR: You don't have shares to cash-out"
        );
        ShareEntity storage share = _getShareWithCreatime(shares, _creationTime);

        share.amount += rewardAmount_;
        share.lastClaimTime = block.timestamp;
    }

    function cashoutAllSharesRewards(address account)
        external
        onlyGuard
        onlyShareOwner(account)
        whenNotPaused
    {
        ShareEntity[] storage shares = _sharesOfUser[account];
        uint256 sharesCount = shares.length;
        require(sharesCount > 0, "share: CREATIME must be higher than zero");
        ShareEntity storage _share;
        for (uint256 i = 0; i < sharesCount; i++) {
            _share = shares[i];
            _share.lastClaimTime = block.timestamp;
        }
    }

    function getSharesCreationTime(address account)
        public
        view
        onlyShareOwner(account)
        returns (string memory)
    {
        ShareEntity[] memory shares = _sharesOfUser[account];
        uint256 sharesCount = shares.length;
        ShareEntity memory _share;
        string memory _creationTimes = _uint2str(shares[0].creationTime);
        string memory separator = "#";

        for (uint256 i = 1; i < sharesCount; i++) {
            _share = shares[i];

            _creationTimes = string(
                abi.encodePacked(
                    _creationTimes,
                    separator,
                    _uint2str(_share.creationTime)
                )
            );
        }
        return _creationTimes;
    }

    function getSharesLastClaimTime(address account)
        public
        view
        onlyShareOwner(account)
        returns (string memory)
    {
        ShareEntity[] memory shares = _sharesOfUser[account];
        uint256 sharesCount = shares.length;
        ShareEntity memory _share;
        string memory _lastClaimTimes = _uint2str(shares[0].lastClaimTime);
        string memory separator = "#";

        for (uint256 i = 1; i < sharesCount; i++) {
            _share = shares[i];

            _lastClaimTimes = string(
                abi.encodePacked(
                    _lastClaimTimes,
                    separator,
                    _uint2str(_share.lastClaimTime)
                )
            );
        }
        return _lastClaimTimes;
    }

    function updateToken(address newToken) external onlyOwner {
        token = newToken;
    }

    function updateReward(uint8 newVal) external onlyOwner {
        rewardPerShare = newVal;
    }

    function updateMinPrice(uint256 newVal) external onlyOwner {
        minPrice = newVal;
    }

    function updateBoostMultipliers(uint8[] calldata newVal) external onlyOwner {
        require(newVal.length == 3, "Wrong length");
        _boostMultipliers = newVal;
    }

    function updateBoostRequiredDays(uint8[] calldata newVal) external onlyOwner {
        require(newVal.length == 3, "Wrong length");
        _boostRequiredDays = newVal;
    }

    function getMinPrice() external view returns (uint256) {
        return minPrice;
    }

    function getShareNumberOf(address account) external view returns (uint256) {
        return shareOwners.get(account);
    }

    function isShareOwner(address account) public view returns (bool) {
        return shareOwners.get(account) > 0;
    }

    function getAllShares(address account) external view returns (ShareEntity[] memory) {
        return _sharesOfUser[account];
    }

    function getIndexOfKey(address account) external view onlyOwner returns (int256) {
        require(account != address(0));
        return shareOwners.getIndexOfKey(account);
    }

    function burn(uint256 index) external onlyOwner {
        require(index < shareOwners.size());
        shareOwners.remove(shareOwners.getKeyAtIndex(index));
    }
}

