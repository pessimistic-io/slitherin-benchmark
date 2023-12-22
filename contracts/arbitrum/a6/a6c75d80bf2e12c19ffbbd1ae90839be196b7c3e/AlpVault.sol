// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./OwnableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IWater.sol";
import "./IAlpManager.sol";
import "./ISmartChefInitializable.sol";
import "./IMasterChef.sol";
import "./IAlpRewardHandler.sol";
import "./IAlpVault.sol";

contract AlpVault is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, ERC20BurnableUpgradeable, IAlpVault {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    IWater public water;
    address public USDC;
    address private mFeeReceiver;

    uint256 public DTVLimit;
    uint256 public DTVSlippage;
    uint256 public MCPID;
    uint256 private defaultDebtAdjustment;
    uint256 private mFeePercent;

    StrategyMisc public strategyMisc;
    StrategyAddresses public strategyAddresses;
    FeeConfiguration public feeConfiguration;

    address[] public allUsers;

    mapping(address => bool) public isWhitelistedAsset;
    mapping(address => bool) public allowedClosers;
    mapping(address => bool) public allowedSenders;

    mapping(address => bool) public burner;
    mapping(address => bool) public isUser;
    mapping(address => UserInfo[]) public userInfo;

    uint256[50] private __gaps;

    modifier InvalidID(uint256 positionId, address user) {
        require(positionId < userInfo[user].length, "ApxVault: !valid");
        _;
    }

    modifier onlyBurner() {
        require(burner[msg.sender], "Not allowed to burn");
        _;
    }

    modifier zeroAddress(address addr) {
        require(addr != address(0), "Zero address");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _water, address _usdc) external initializer {
        defaultDebtAdjustment = 1e18;
        strategyMisc.MAX_LEVERAGE = 10_000;
        strategyMisc.MIN_LEVERAGE = 2_000;
        strategyMisc.DECIMAL = 1e18;
        strategyMisc.MAX_BPS = 100_000;
        water = IWater(_water);
        USDC = _usdc;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __ERC20_init("ALPPOD", "ALPPOD");
    }

    function setWhitelistedAsset(address token, bool status) external onlyOwner {
        isWhitelistedAsset[token] = status;
        emit SetWhitelistedAsset(token, status);
    }

    function setMFeeConfig(uint256 _mFeePercent, address _mFeeReceiver) external onlyOwner {
        mFeePercent = _mFeePercent;
        mFeeReceiver = _mFeeReceiver;
    }

    function setBurner(address _burner, bool _allowed) public onlyOwner zeroAddress(_burner) {
        burner[_burner] = _allowed;
        emit SetBurner(_burner, _allowed);
    }

    function setCloser(address _closer, bool _allowed) public onlyOwner zeroAddress(_closer) {
        allowedClosers[_closer] = _allowed;
        emit SetAllowedClosers(_closer, _allowed);
    }

    function setAllowed(address _sender, bool _allowed) public onlyOwner zeroAddress(_sender) {
        allowedSenders[_sender] = _allowed;
        emit SetAllowedSenders(_sender, _allowed);
    }

    function setStrategyAddress(
        address _diamond,
        address _smartChef,
        address _apolloXp,
        address _rewardHandler,
        address _masterChef,
        uint256 _pid
    ) external onlyOwner {
        strategyAddresses.alpDiamond = _diamond;
        strategyAddresses.smartChef = _smartChef;
        strategyAddresses.apolloXP = _apolloXp;
        strategyAddresses.alpRewardHandler = _rewardHandler;
        strategyAddresses.masterChef = _masterChef;
        MCPID = _pid;
        emit SetStrategyAddresses(_diamond, _smartChef, _apolloXp);
    }

    function setFeeConfiguration(
        address _feeReceiver,
        uint256 _withdrawalFee,
        address _waterFeeReceiver,
        uint256 _liquidatorsRewardPercentage,
        uint256 _fixedFeeSplit
    ) external onlyOwner {
        feeConfiguration.feeReceiver = _feeReceiver;
        feeConfiguration.withdrawalFee = _withdrawalFee;
        feeConfiguration.waterFeeReceiver = _waterFeeReceiver;
        feeConfiguration.liquidatorsRewardPercentage = _liquidatorsRewardPercentage;
        feeConfiguration.fixedFeeSplit = _fixedFeeSplit;
        emit SetFeeConfiguration(_feeReceiver, _withdrawalFee, _waterFeeReceiver, _liquidatorsRewardPercentage, _fixedFeeSplit);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function migrateLP(address _newSmartChef) external onlyOwner {
        // get total deposited amount
        uint256 totalDeposited = ISmartChefInitializable(strategyAddresses.smartChef).userInfo(address(this)).amount;
        // withdraw all from old smart chef
        ISmartChefInitializable(strategyAddresses.smartChef).withdraw(totalDeposited);
        // approve new smart chef to deposit
        IERC20Upgradeable(strategyAddresses.apolloXP).safeIncreaseAllowance(_newSmartChef, totalDeposited);
        // deposit to new smart chef
        ISmartChefInitializable(_newSmartChef).deposit(totalDeposited);
        // update smart chef address
        strategyAddresses.smartChef = _newSmartChef;
        emit MigrateLP(_newSmartChef, totalDeposited);
    }

    function setDTVLimit(uint256 _DTVLimit, uint256 _DTVSlippage) public onlyOwner {
        require(_DTVSlippage <= 1000, "Slippage < 1000");
        DTVLimit = _DTVLimit;
        DTVSlippage = _DTVSlippage;
    }

    function getAlpPrice() public view returns (uint256) {
        return IAlpManager(strategyAddresses.alpDiamond).alpPrice();
    }

    function getStakedInfo() public view returns (uint256 amountDeposited, uint256 rewards) {
        ISmartChefInitializable.UserInfo memory _userInfo = ISmartChefInitializable(strategyAddresses.smartChef).userInfo(address(this));
        return (_userInfo.amount, ISmartChefInitializable(strategyAddresses.smartChef).pendingReward(address(this)));
    }

    function getAlpCoolingDuration() public view returns (uint256) {
        return IAlpManager(strategyAddresses.alpDiamond).coolingDuration();
    }

    function getAllUsers() public view returns (address[] memory) {
        return allUsers;
    }

    function getAggregatePosition(address _user) public view returns (uint256) {
        uint256 aggregatePosition;
        for (uint256 i = 0; i < userInfo[_user].length; i++) {
            UserInfo memory _userInfo = userInfo[_user][i];
            if (!_userInfo.liquidated) {
                aggregatePosition += userInfo[_user][i].position;
            }
        }
        return aggregatePosition;
    }

    function getTotalNumbersOfOpenPositionBy(address _user) public view returns (uint256) {
        return userInfo[_user].length;
    }

    function getUpdatedDebt(
        uint256 _positionID,
        address _user
    ) public view returns (uint256 currentDTV, uint256 currentPosition, uint256 currentDebt) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        if (_userInfo.closed || _userInfo.liquidated) return (0, 0, 0);

        uint256 previousValueInUSDC;
        // Get the current position and previous value in USDC using the `getCurrentPosition` function
        (currentPosition, previousValueInUSDC) = getCurrentPosition(_positionID, _userInfo.position, _user);
        uint256 leverage = _userInfo.leverageAmount;

        // Calculate the current DTV by dividing the amount owed to water by the current position
        currentDTV = (leverage * strategyMisc.DECIMAL) / currentPosition;
        // Return the current DTV, current position, and amount owed to water
        return (currentDTV, currentPosition, leverage);
    }

    function getCurrentPosition(
        uint256 _positionID,
        uint256 _shares,
        address _user
    ) public view returns (uint256 currentPosition, uint256 previousValueInUSDC) {
        UserInfo memory _userInfo = userInfo[_user][_positionID];
        return (_convertALPToUSDC(_shares, getAlpPrice()), _convertALPToUSDC(_shares, _userInfo.price));
    }

    function handleAndCompoundRewards() public returns (uint256) {
        // withdraw all from old smart chef
        if(ISmartChefInitializable(strategyAddresses.smartChef).userInfo(address(this)).amount > 0) {
            ISmartChefInitializable(strategyAddresses.smartChef).withdraw(0);
        }
        // get rewards token address from smart chef
        address rewardToken = ISmartChefInitializable(strategyAddresses.smartChef).rewardToken();
        // get balance of address(this) in reward token
        uint256 balance = IERC20Upgradeable(rewardToken).balanceOf(address(this));

        if (balance > 0) {
            (uint256 toOwner, uint256 toWater, uint256 toVodkaUsers) = IAlpRewardHandler(strategyAddresses.alpRewardHandler).getVodkaSplit(
                balance
            );

            IERC20Upgradeable(rewardToken).transfer(strategyAddresses.alpRewardHandler, balance);

            IAlpRewardHandler(strategyAddresses.alpRewardHandler).distributeCAKE(toVodkaUsers);
            IAlpRewardHandler(strategyAddresses.alpRewardHandler).distributeRewards(toOwner, toWater);
            emit CAKEHarvested(toVodkaUsers);
            return toVodkaUsers;
        }

        return 0;
    }

    // @todo add cool down time for each users
    function openPosition(address _token, uint256 _amount, uint256 _leverage) external {
        require(_leverage >= strategyMisc.MIN_LEVERAGE && _leverage <= strategyMisc.MAX_LEVERAGE, "ApxVault: Invalid leverage");
        require(_amount > 0, "ApxVault: amount must > zero");
        require(isWhitelistedAsset[_token], "ApxVault: !whitelisted");

        IAlpRewardHandler(strategyAddresses.alpRewardHandler).claimCAKERewards(msg.sender);

        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // get leverage amount
        uint256 leveragedAmount = ((_amount * _leverage) / 1000) - _amount;
        bool status = water.lend(leveragedAmount, address(this));
        require(status, "Water: Lend failed");
        // add leverage amount to amount
        uint256 sumAmount = _amount + leveragedAmount;

        uint256 balanceBefore = IERC20Upgradeable(strategyAddresses.apolloXP).balanceOf(address(this));
        IERC20Upgradeable(_token).safeIncreaseAllowance(strategyAddresses.alpDiamond, sumAmount);
        // @todo since the price of alp is known, we can calculate the min alp required
        IAlpManager(strategyAddresses.alpDiamond).mintAlp(_token, sumAmount, 0, false);
        uint256 balanceAfter = IERC20Upgradeable(strategyAddresses.apolloXP).balanceOf(address(this));
        uint256 mintedAmount = balanceAfter - balanceBefore;
        // approve smart chef to deposit minted amount
        IERC20Upgradeable(strategyAddresses.apolloXP).safeIncreaseAllowance(strategyAddresses.smartChef, mintedAmount);
        // deposit minted amount to smart chef
        ISmartChefInitializable(strategyAddresses.smartChef).deposit(mintedAmount);

        UserInfo memory _userInfo = UserInfo({
            user: msg.sender,
            deposit: _amount,
            leverage: _leverage,
            position: mintedAmount,
            price: getAlpPrice(),
            liquidated: false,
            closedPositionValue: 0,
            liquidator: address(0),
            closePNL: 0,
            leverageAmount: leveragedAmount,
            positionId: userInfo[msg.sender].length,
            closed: false
        });

        //frontend helper to fetch all users and then their userInfo
        if (isUser[msg.sender] == false) {
            isUser[msg.sender] = true;
            allUsers.push(msg.sender);
        }

        userInfo[msg.sender].push(_userInfo);

        // mint pod
        _mint(msg.sender, mintedAmount);
        IAlpRewardHandler(strategyAddresses.alpRewardHandler).setDebtRecordCAKE(msg.sender);
        emit OpenPosition(msg.sender, _leverage, _amount, mintedAmount, userInfo[msg.sender].length - 1, block.timestamp);
    }

    function closePosition(uint256 _positionID, address _user) external InvalidID(_positionID, _user) nonReentrant {
        // Retrieve user information for the given position
        UserInfo storage _userInfo = userInfo[_user][_positionID];
        // Validate that the position is not liquidated
        require(!_userInfo.liquidated, "ApxVault: position is liquidated");
        // Validate that the position has enough shares to close
        require(_userInfo.position > 0, "ApxVault: position !enough to close");
        require(allowedClosers[msg.sender] || msg.sender == _userInfo.user, "ApxVault: !allowed to close position");

        IAlpRewardHandler(strategyAddresses.alpRewardHandler).claimCAKERewards(_user);
        // Struct to store intermediate data during calculation
        CloseData memory closeData;
        (closeData.currentDTV, , ) = getUpdatedDebt(_positionID, _user);

        if (closeData.currentDTV >= (DTVSlippage * DTVLimit) / 1000) {
            revert("liquidation");
        }

        _handlePODToken(_userInfo.user, _userInfo.position);

        // withdraw staked amount from smart chef
        ISmartChefInitializable(strategyAddresses.smartChef).withdraw(_userInfo.position);

        // @todo since the price of alp is known, we can calculate the min usdc required
        uint256 balanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
        // approve alp diamond to burn alp
        IERC20Upgradeable(strategyAddresses.apolloXP).safeIncreaseAllowance(strategyAddresses.alpDiamond, _userInfo.position);
        // @todo wait for cooldown period to end
        IAlpManager(strategyAddresses.alpDiamond).burnAlp(USDC, _userInfo.position, 0, address(this));
        uint256 balanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
        closeData.returnedValue = balanceAfter - balanceBefore;
        closeData.originalPosAmount = _userInfo.deposit + _userInfo.leverageAmount;

        if (closeData.returnedValue > closeData.originalPosAmount) {
            closeData.profits = closeData.returnedValue - closeData.originalPosAmount;
        }

        if (closeData.profits > 0) {
            (closeData.waterProfits, closeData.mFee, closeData.userShares) = _getProfitSplit(closeData.profits, _userInfo.leverage);
        }

        if (closeData.returnedValue < _userInfo.leverageAmount + closeData.waterProfits) {
            _userInfo.liquidator = msg.sender;
            _userInfo.liquidated = true;
            closeData.waterRepayment = closeData.returnedValue;
        } else {
            closeData.waterRepayment = _userInfo.leverageAmount;
            closeData.toLeverageUser = (closeData.returnedValue - closeData.waterRepayment) - closeData.waterProfits - closeData.mFee;
        }

        IERC20Upgradeable(USDC).safeIncreaseAllowance(address(water), closeData.waterRepayment);
        closeData.success = water.repayDebt(_userInfo.leverageAmount, closeData.waterRepayment);
        _userInfo.position = 0;
        _userInfo.leverageAmount = 0;
        _userInfo.closed = true;

        if (_userInfo.liquidated) {
            return;
        }

        if (closeData.waterProfits > 0) {
            IERC20Upgradeable(USDC).safeTransfer(feeConfiguration.waterFeeReceiver, closeData.waterProfits);
        }

        if (closeData.mFee > 0) {
            IERC20Upgradeable(USDC).safeTransfer(mFeeReceiver, closeData.mFee);
        }

        // take protocol fee
        uint256 amountAfterFee;
        if (feeConfiguration.withdrawalFee > 0) {
            uint256 fee = (closeData.toLeverageUser * feeConfiguration.withdrawalFee) / strategyMisc.MAX_BPS;
            IERC20Upgradeable(USDC).safeTransfer(feeConfiguration.feeReceiver, fee);
            amountAfterFee = closeData.toLeverageUser - fee;
        } else {
            amountAfterFee = closeData.toLeverageUser;
        }

        IERC20Upgradeable(USDC).safeTransfer(_user, amountAfterFee);

        _userInfo.closedPositionValue += closeData.returnedValue;
        _userInfo.closePNL += amountAfterFee;
        IAlpRewardHandler(strategyAddresses.alpRewardHandler).setDebtRecordCAKE(_user);
        emit ClosePosition(_user, amountAfterFee, _positionID, block.timestamp, _userInfo.position, _userInfo.leverage, block.timestamp);
    }

    function liquidatePosition(uint256 _positionId, address _user) external nonReentrant {
        UserInfo storage _userInfo = userInfo[_user][_positionId];
        require(!_userInfo.liquidated, "Sake: Already liquidated");
        require(_userInfo.user != address(0), "Sake: liquidation request does not exist");
        (uint256 currentDTV, , ) = getUpdatedDebt(_positionId, _user);

        if (currentDTV >= (DTVSlippage * DTVLimit) / 1000) {
            revert("liquidation");
        }
        IAlpRewardHandler(strategyAddresses.alpRewardHandler).claimCAKERewards(_user);

        _handlePODToken(_user, _userInfo.position);

        IERC20Upgradeable(strategyAddresses.apolloXP).safeIncreaseAllowance(strategyAddresses.alpDiamond, _userInfo.position);

        uint256 usdcBalanceBefore = IERC20Upgradeable(USDC).balanceOf(address(this));
        IAlpManager(strategyAddresses.alpDiamond).burnAlp(USDC, _userInfo.position, 0, address(this));

        uint256 usdcBalanceAfter = IERC20Upgradeable(USDC).balanceOf(address(this));
        uint256 returnedValue = usdcBalanceAfter - usdcBalanceBefore;

        _userInfo.liquidator = msg.sender;
        _userInfo.liquidated = true;

        uint256 liquidatorReward = (returnedValue * feeConfiguration.liquidatorsRewardPercentage) / strategyMisc.MAX_BPS;
        uint256 amountAfterLiquidatorReward = returnedValue - liquidatorReward;

        IERC20Upgradeable(USDC).safeIncreaseAllowance(address(water), amountAfterLiquidatorReward);
        bool success = water.repayDebt(_userInfo.leverageAmount, amountAfterLiquidatorReward);
        require(success, "Water: Repay failed");
        IERC20Upgradeable(USDC).safeTransfer(msg.sender, liquidatorReward);
        IAlpRewardHandler(strategyAddresses.alpRewardHandler).setDebtRecordCAKE(_user);
        emit Liquidated(_user, _positionId, msg.sender, returnedValue, liquidatorReward, block.timestamp);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        require(allowedSenders[from] || allowedSenders[to] || allowedSenders[spender], "ERC20: transfer not allowed");
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address ownerOf = _msgSender();
        require(allowedSenders[ownerOf] || allowedSenders[to], "ERC20: transfer not allowed");
        _transfer(ownerOf, to, amount);
        return true;
    }

    function burn(uint256 amount) public virtual override onlyBurner {
        _burn(_msgSender(), amount);
    }

    function _handlePODToken(address _user, uint256 position) internal {
        if (strategyAddresses.masterChef != address(0)) {
            uint256 userBalance = balanceOf(_user);
            if (userBalance >= position) {
                _burn(_user, position);
            } else {
                _burn(_user, userBalance);
                uint256 remainingPosition = position - userBalance;
                IMasterChef(strategyAddresses.masterChef).unstakeAndLiquidate(MCPID, _user, remainingPosition);
            }
        } else {
            _burn(_user, position);
        }
    }

    function _getProfitSplit(uint256 _profit, uint256 _leverage) internal view returns (uint256, uint256, uint256) {
        uint256 split = (feeConfiguration.fixedFeeSplit * _leverage + (feeConfiguration.fixedFeeSplit * 10000)) / 100;
        uint256 toWater = (_profit * split) / 10000;
        uint256 mFee = (_profit * mFeePercent) / 10000;
        uint256 toSakeUser = _profit - (toWater + mFee);

        return (toWater, mFee, toSakeUser);
    }

    function _convertALPToUSDC(uint256 _amount, uint256 _alpPrice) internal pure returns (uint256) {
        return (_amount * _alpPrice) / (10 ** 6);
    }
}

