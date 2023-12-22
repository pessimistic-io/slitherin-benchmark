//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC20.sol";

contract LaunchPadWhitelist is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event TokenClaimed(address indexed wallet, uint256 amount);
    event TokenBought(address indexed wallet, uint256 amount);

    struct VestingInfo {
        address wallet;
        uint256 amount;
        uint256 paymentAmount;
        uint256 leftOverAmount;
        uint256 upfrontAmount;
        bool upfrontAmountClaimed;
        uint256 released;
        uint256 lastReleasedAt;
    }

    uint256 public startDate;
    uint256 public endDate;
    uint256 public tgeDate;
    uint256 public lockDuration;
    uint256 public vestDuration;
    uint256 public vestInterval;
    uint256 public upfrontPercent;
    address public paymentReceiveWallet;

    mapping(address => VestingInfo) public vestingInfo;
    address[] public vestingInfoAddresses;
    mapping(address => bool) public whitelist;
    mapping(address => uint256) public whitelistAmount;

    IERC20 public paymentToken;
    IERC20 public token;
    uint256 stableCoinAmount;
    uint256 tokenAmount;
    uint256 currentSoldStableCoinAmount;
    uint256 totalStableCoinAmount;
    uint256 public packAmount;

    // only owner or added beneficiaries can release the vesting amount
    modifier onlyVestingUser() {
        require(
            vestingInfo[_msgSender()].amount > 0,
            "You're not in the vesting list."
        );
        _;
    }

    function setTokenParams(
        address _token,
        address _paymentToken,
        uint256 _stableCoinAmount,
        uint256 _tokenAmount,
        uint256 _totalStableCoinAmount,
        uint256 _packAmount
    ) external onlyOwner {
        token = IERC20(_token);
        paymentToken = IERC20(_paymentToken);
        stableCoinAmount = _stableCoinAmount;
        tokenAmount = _tokenAmount;
        totalStableCoinAmount = _totalStableCoinAmount;
        packAmount = _packAmount;
    }

    function setVestingParams(
        uint256 _upfrontPercent,
        uint256 _vestDuration,
        uint256 _vestInterval,
        uint256 _lockDuration,
        address _paymentReceiveWallet
    ) public onlyOwner {
        upfrontPercent = _upfrontPercent;
        lockDuration = _lockDuration;
        vestDuration = _vestDuration;
        vestInterval = _vestInterval;
        paymentReceiveWallet = _paymentReceiveWallet;
    }

    /**
     * @dev Set launch pad timeline
     */
    function setTimelineParams(
        uint256 _startDate,
        uint256 _endDate,
        uint256 _tgeDate
    ) public onlyOwner {
        startDate = _startDate;
        endDate = _endDate;
        tgeDate = _tgeDate;
    }

    /**
     * @dev  Buy launch pad token
     */
    function buyTokens(uint256 _paymentAmount) public {
        require(
            stableCoinAmount > 0 && tokenAmount > 0,
            "Token exchange rate has not set yet."
        );

        require(
            _paymentAmount % packAmount == 0,
            "Stable coin amount is not valid"
        );

        require(startDate < block.timestamp, "Token sale has not started yet.");

        require(
            endDate == 0 || block.timestamp <= endDate,
            "To late to join this pool. Please wait for next sale pool"
        );

        require(whitelist[_msgSender()], "Address is not in whitelist.");

        require(
            paymentToken.balanceOf(_msgSender()) >= _paymentAmount,
            "Your balance is not enough to buy tokens."
        );

        require(
            paymentToken.allowance(_msgSender(), address(this)) >=
                _paymentAmount,
            "Invalid allowance to buy Token sale tokens."
        );

        if (
            currentSoldStableCoinAmount.add(_paymentAmount) >
            totalStableCoinAmount
        ) {
            _paymentAmount =
                totalStableCoinAmount -
                currentSoldStableCoinAmount;
        }

        uint256 paymentAmount = vestingInfo[_msgSender()].paymentAmount.add(
            _paymentAmount
        );

        require(
            paymentAmount <= whitelistAmount[_msgSender()],
            "Buy exceed the allowed amount."
        );

        uint256 newTokenAmount = (paymentAmount * tokenAmount) /
            stableCoinAmount;
        uint256 upfrontAmount = newTokenAmount.mul(upfrontPercent).div(100);
        uint256 leftOverAmount = newTokenAmount.sub(upfrontAmount);
        // transfer payment to address
        paymentToken.safeTransferFrom(
            _msgSender(),
            paymentReceiveWallet,
            _paymentAmount
        );

        if (vestingInfo[_msgSender()].amount > 0) {
            vestingInfo[_msgSender()].amount = newTokenAmount;
            vestingInfo[_msgSender()].paymentAmount = paymentAmount;
            vestingInfo[_msgSender()].leftOverAmount = leftOverAmount;
            vestingInfo[_msgSender()].upfrontAmount = upfrontAmount;
        } else {
            vestingInfo[_msgSender()] = VestingInfo({
                wallet: _msgSender(),
                amount: newTokenAmount,
                paymentAmount: _paymentAmount,
                leftOverAmount: leftOverAmount,
                upfrontAmount: upfrontAmount,
                released: 0,
                lastReleasedAt: 0,
                upfrontAmountClaimed: false
            });
            vestingInfoAddresses.push(_msgSender());
        }

        currentSoldStableCoinAmount = currentSoldStableCoinAmount.add(
            _paymentAmount
        );
        emit TokenBought(_msgSender(), tokenAmount);
    }

    /**
     * @dev Get launch pad stats information.
     */
    function information()
        public
        view
        returns (
            uint256 _startDate,
            uint256 _endDate,
            uint256 _tokenAmount,
            uint256 _packAmount,
            uint256 _currentSoldStableCoinAmount,
            uint256 _totalStableCoinAmount,
            uint256 _contributors
        )
    {
        return (
            startDate,
            endDate,
            tokenAmount,
            packAmount,
            currentSoldStableCoinAmount,
            totalStableCoinAmount,
            vestingInfoAddresses.length
        );
    }

    /**
     * @dev Get new vested amount of beneficiary base on vesting schedule of this beneficiary.
     */
    function releasableAmount(
        address _wallet
    ) public view returns (uint256, uint256, uint256) {
        VestingInfo memory info = vestingInfo[_wallet];
        if (info.amount == 0) {
            return (0, 0, block.timestamp);
        }

        (uint256 _vestedAmount, uint256 _lastIntervalDate) = vestedAmount(
            _wallet
        );

        return (
            _vestedAmount,
            _vestedAmount.sub(info.released),
            _lastIntervalDate
        );
    }

    /**24*60*60
     * @dev Get total vested amount of beneficiary base on vesting schedule of this beneficiary.
     */
    function vestedAmount(
        address _wallet
    ) public view returns (uint256, uint256) {
        VestingInfo memory info = vestingInfo[_wallet];
        require(info.amount > 0, "The beneficiary's address cannot be found");

        if (tgeDate == 0) {
            return (info.released, info.lastReleasedAt);
        }

        if (block.timestamp < tgeDate) {
            return (info.released, info.lastReleasedAt);
        }

        uint256 vestingStartDate = tgeDate.add(lockDuration);

        // No vesting (All amount unlock at the purchase time)
        if (vestDuration == 0) {
            return (info.amount, vestingStartDate);
        }

        // Vesting has not started yet
        if (block.timestamp < vestingStartDate) {
            return (info.upfrontAmount, info.lastReleasedAt);
        }

        // Vesting is done
        if (block.timestamp >= vestingStartDate.add(vestDuration)) {
            return (info.amount, vestingStartDate.add(vestDuration));
        }

        // Vesting is interval counter
        uint256 totalVestedAmount = info.upfrontAmount;
        uint256 lastIntervalDate = info.lastReleasedAt > 0
            ? info.lastReleasedAt
            : vestingStartDate;

        uint256 multiplyInterval = (block.timestamp - vestingStartDate) /
            vestInterval;

        uint256 maxInterval = vestDuration / vestInterval;
        uint256 newVestedAmount = info.leftOverAmount.mul(multiplyInterval).div(
            maxInterval
        );
        totalVestedAmount = totalVestedAmount.add(newVestedAmount);

        return (totalVestedAmount, lastIntervalDate);
    }

    /**
     * @dev Release vested tokens to a specified beneficiary.
     */
    function releaseTo(
        address _wallet,
        uint256 _amount,
        uint256 _lastIntervalDate
    ) internal returns (bool) {
        VestingInfo storage info = vestingInfo[_wallet];
        if (block.timestamp < _lastIntervalDate) {
            return false;
        }
        // Update beneficiary information
        if (info.upfrontAmountClaimed == false) {
            info.upfrontAmountClaimed = true;
        }
        info.released = info.released.add(_amount);
        info.lastReleasedAt = _lastIntervalDate;

        // Transfer new released amount to vesting beneficiary
        token.safeTransfer(_wallet, _amount);
        // Emit event to of new release
        emit TokenClaimed(_wallet, _amount);
        return true;
    }

    /**
     * @dev Release vested tokens to current beneficiary.
     */
    function claimTokens() public onlyVestingUser {
        // Calculate the releasable amount
        (
            ,
            uint256 _newReleaseAmount,
            uint256 _lastIntervalDate
        ) = releasableAmount(_msgSender());

        // Release new vested token to the beneficiary

        if (_newReleaseAmount > 0) {
            releaseTo(_msgSender(), _newReleaseAmount, _lastIntervalDate);
        }
    }

    function addWhitelist(
        address[] calldata _wallets,
        uint256[] calldata amounts
    ) public onlyOwner {
        for (uint256 i = 0; i < _wallets.length; i++) {
            whitelist[_wallets[i]] = true;
            whitelistAmount[_wallets[i]] = amounts[i];
        }
    }
}

