// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./ChamSlizSolidManager.sol";
import "./ISolidLizardProxy.sol";
import "./IVeToken.sol";
import "./IVoter.sol";
import "./ISolidlyRouter.sol";

contract ChamSlizSolidStaker is ERC20, ChamSlizSolidManager, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Addresses used
    ISolidLizardProxy public immutable proxy;

    // Want token and our NFT Token ID
    IERC20 public immutable want;
    IVeToken public immutable ve;
    IVoter public immutable solidVoter;
    ISolidlyRouter public router;

    // Max Lock time, Max variable used for reserve split and the reserve rate.
    uint256 public constant MAX = 10000; // 100%
    uint256 public constant MAX_RATE = 1e18;
    // Vote weight decays linearly over time. Lock time cannot be more than `MAX_LOCK` (4 years).
    uint256 public constant MAX_LOCK = 365 days * 4;
    uint256 public veMintRatio = 1e18;
    uint256 public maximumNFTAmountRate = 1e18;
    uint256 public reserveRate;

    bool public isAutoIncreaseLock = true;
    bool public isCheckMaxAmountOfNFTOnDeposit = false;

    // Pause for deposit 
    bool public isPausedDepositSliz;
    bool public isPausedDepositVeSliz;

    bool public enabledPenaltyFee;
    uint256 public penaltyRate = 0.25e18; // 0.25
    uint256 public maxBurnRate = 50; // 0.5%
    uint256 public maxPegReserve = 0.6e18;

    address[] public excluded;
    address public constant deadWallet = 0x000000000000000000000000000000000000dEaD;

    mapping (address => bool) public marketLpPairs; // LP Pairs
    uint256 public taxSellingPercent = 0;
    mapping(address => bool) public excludedSellingTaxAddresses;

    uint256 public taxBuyingPercent = 0;
    mapping(address => bool) public excludedBuyingTaxAddresses;

    // Our on chain events.
    event CreateLock(
        address indexed user,
        uint256 amount,
        uint256 unlockTime
    );

    event Release(address indexed user, uint256 amount);
    event AutoIncreaseLock(bool _enabled);
    event EnabledPenaltyFee(bool _enabled);
    event CheckMaxAmountOfNFTOnDeposit(bool _enabled);
    event PauseDepositSliz(bool _paused);
    event PauseDepositVeSliz(bool _paused);
    event IncreaseTime(
        address indexed user,
        uint256 unlockTime
    );
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event ClaimVeEmissions(
        address indexed user,
        uint256 amount
    );
    event UpdatedVeMintRatio(uint256 newRatio);
    event UpdatedMaximumNFTAmountRate(uint256 newRate);
    event UpdatedReserveRate(uint256 newRate);
    event SetMaxBurnRate(uint256 oldRate, uint256 newRate);
    event SetMaxPegReserve(uint256 oldValue, uint256 newValue);
    event SetPenaltyRate(uint256 oldValue, uint256 newValue);
    event GrantExclusion(address indexed account);
    event RevokeExclusion(address indexed account);
    event SetTaxSellingPercent(uint256 oldValue, uint256 newValue);
    event SetTaxBuyingPercent(uint256 oldValue, uint256 newValue);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _reserveRate,
        address _proxy,
        address _keeper,
        address _voter,
        address _taxWallet,
        address _polWallet,
        address _daoWallet
    )
        ERC20(_name, _symbol)
        ChamSlizSolidManager(_keeper, _voter, _taxWallet, _polWallet, _daoWallet)
    {
        reserveRate = _reserveRate;
        proxy = ISolidLizardProxy(_proxy);
        want = IERC20(proxy.SLIZ());
        ve = IVeToken(proxy.ve());
        solidVoter = IVoter(proxy.solidVoter());
        router = ISolidlyRouter(proxy.router());

        excluded.push(deadWallet);
    }

    // Deposit all want for a user.
    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    // Deposit an amount of want.
    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    // Deposit an amount of want in veSliz.
    function depositVeSliz(
        uint256 _tokenId
    ) external nonReentrant whenNotPaused {
        require(!isPausedDepositVeSliz, "ChamSlizStaker: PAUSED");
        lock();
        (uint256 _lockedAmount, ) = ve.locked(_tokenId);
        if (_lockedAmount > 0) {
            if (isCheckMaxAmountOfNFTOnDeposit) {
                require(
                    _lockedAmount <= (balanceOfWant() * maximumNFTAmountRate) / MAX_RATE,
                    "ChamSlizStaker: INSUFFICIENT_RESERVE"
                );
            }
            ve.transferFrom(msg.sender, address(proxy), _tokenId);
            proxy.merge(_tokenId);
            uint amountChamSLIZMint = (_lockedAmount * MAX_RATE) / veMintRatio;
            _mint(msg.sender, amountChamSLIZMint);
            emit Deposit(_lockedAmount);
        }
    }

    // Internal: Deposits Want and mint CeWant, checks for ve increase opportunities first.
    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        require(!isPausedDepositSliz, "ChamSlizStaker: PAUSED");
        lock();
        uint256 _balanceBefore = balanceOfWant();
        want.safeTransferFrom(msg.sender, address(this), _amount);
        _amount = balanceOfWant() - _balanceBefore; // Additional check for deflationary tokens.

        if (_amount > 0) {
            _mint(msg.sender, _amount);
            emit Deposit(totalWant());
        }
    }

    // Deposit more in ve and up lock_time.
    function lock() public {
        if (totalWant() > 0) {
            (, , bool shouldIncreaseLock) = lockInfo();
            if (balanceOfWant() > requiredReserve()) {
                uint256 availableBalance = balanceOfWant() - requiredReserve();
                want.safeTransfer(address(proxy), availableBalance);
                proxy.increaseAmount(availableBalance);
            }
            // Extend max lock
            if (shouldIncreaseLock) proxy.increaseUnlockTime();
        }
    }

    // Withdraw capable if we have enough Want in the contract.
    function withdraw(uint256 _amount) external {
        require(
            _amount <= withdrawableBalance(),
            "ChamSlizStaker: INSUFFICIENCY_AMOUNT_OUT"
        );

        _burn(msg.sender, _amount);
        if (enabledPenaltyFee) {
            uint256 maxAmountBurning = ((circulatingSupply() + _amount) * maxBurnRate) / MAX;
            require(
                _amount <= maxAmountBurning,
                "ChamSlizStaker: Over max burning amount"
            );

            uint256 penaltyAmount = calculatePenaltyFee(_amount);
            if (penaltyAmount > 0) {
                _amount = _amount - penaltyAmount;

                // tax
                uint256 taxAmount = penaltyAmount / 2;
                if (taxAmount > 0) _mint(taxWallet, taxAmount);

                // transfer into a dead address
                uint256 burnAmount = penaltyAmount - taxAmount;
                if (burnAmount > 0) _mint(deadWallet, burnAmount);
            }
        }

        want.safeTransfer(msg.sender, _amount);
        emit Withdraw(totalWant());
    }

    // Total Want in ve contract and CeVe contract.
    function totalWant() public view returns (uint256) {
        return balanceOfWant() + balanceOfWantInVe();
    }

    // Our required Want held in the contract to enable withdraw capabilities.
    function requiredReserve() public view returns (uint256 reqReserve) {
        // We calculate allocation for reserve of the total staked in Ve.
        reqReserve = (balanceOfWantInVe() * reserveRate) / MAX;
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // What is our end lock and seconds remaining in lock?
    function lockInfo()
        public
        view
        returns (
            uint256 endTime,
            uint256 secondsRemaining,
            bool shouldIncreaseLock
        )
    {
        (, endTime) = proxy.locked();
        uint256 unlockTime = ((block.timestamp + MAX_LOCK) / 1 weeks) * 1 weeks;
        secondsRemaining = endTime > block.timestamp
            ? endTime - block.timestamp
            : 0;
        shouldIncreaseLock = isAutoIncreaseLock && unlockTime > endTime;
    }

    // Withdrawable Balance for users
    function withdrawableBalance() public view returns (uint256) {
        return balanceOfWant();
    }

    // How many want we got earning?
    function balanceOfWantInVe() public view returns (uint256 wants) {
        (wants, ) = proxy.locked();
    }

    // Claim veToken emissions and increases locked amount in veToken
    function claimVeEmissions() public virtual {
        uint256 _amount = proxy.claimVeEmissions();
        emit ClaimVeEmissions(msg.sender, _amount);
    }

    // Reset current votes
    function resetVote() external onlyVoter {
        proxy.resetVote();
    }

    // Create a new veToken if none is assigned to this address
    function createLock(
        uint256 _amount,
        uint256 _lock_duration
    ) external onlyManager {
        require(_amount > 0, "ChamSlizStaker: ZERO_AMOUNT");
        want.safeTransferFrom(address(msg.sender), address(proxy), _amount);
        proxy.createLock(_amount, _lock_duration);
        _mint(msg.sender, _amount);

        emit CreateLock(msg.sender, _amount, _lock_duration);
    }

    // Release expired lock of a veToken owned by this address
    function release() external onlyOwner {
        (uint endTime, , ) = lockInfo();
        require(endTime <= block.timestamp, "ChamSlizStaker: LOCKED");
        proxy.release();

        emit Release(msg.sender, balanceOfWant());
    }

    // Adjust reserve rate
    function adjustReserve(uint256 _rate) external onlyOwner {
        // validation from 0-50%
        require(_rate <= 5000, "ChamSlizStaker: OUT_OF_RANGE");
        reserveRate = _rate;
        emit UpdatedReserveRate(_rate);
    }

    // Adjust ve Mint Ratio
    function adjustVeMintRatio(uint256 _ratio) external onlyOwner {
        // validation from 1.0 -> 1.5 veSliz to 1.0 chamSliz
        require(
            _ratio >= 1e18 && _ratio <= 1.5e18,
            "ChamSlizStaker: OUT_OF_RANGE"
        );
        veMintRatio = _ratio;
        emit UpdatedVeMintRatio(_ratio);
    }

    // Adjust maximum NFT Amount Rate
    function adjustMaximumNFTAmountRate(uint256 _rate) external onlyOwner {
        // validation from 0 -> 5
        require(_rate <= 5e18, "ChamSlizStaker: OUT_OF_RANGE");
        maximumNFTAmountRate = _rate;
        emit UpdatedMaximumNFTAmountRate(_rate);
    }

    // Enable/Disable Penalty Fee
    function setEnabledPenaltyFee(bool _isEnable) external onlyOwner {
        enabledPenaltyFee = _isEnable;
        emit EnabledPenaltyFee(_isEnable);
    }

    // Pause/Unpause Pause deposit Sliz
    function pauseDepositSliz(bool _isPause) external onlyManager {
        isPausedDepositSliz = _isPause;
        emit PauseDepositSliz(_isPause);
    }

    // Pause/Unpause deposit Ve Sliz
    function pauseDepositVeSliz(bool _isPause) external onlyManager {
        isPausedDepositVeSliz = _isPause;
        emit PauseDepositVeSliz(_isPause);
    }

    // Enable/Disable Check Maximum Amount Of NFT On Deposit
    function setCheckMaxAmountOfNFTOnDeposit(bool _isEnable) external onlyOwner {
        isCheckMaxAmountOfNFTOnDeposit = _isEnable;
        emit CheckMaxAmountOfNFTOnDeposit(_isEnable);
    }

    function setPenaltyRate(uint256 _rate) external onlyOwner {
        // validation from 0-0.5
        require(_rate <= MAX_RATE / 2, "ChamSlizStaker: OUT_OF_RANGE");
        emit SetPenaltyRate(penaltyRate, _rate);
        penaltyRate = _rate;
    }

    // Enable/Disable auto increase lock
    function setAutoIncreaseLock(bool _isEnable) external onlyOwner {
        isAutoIncreaseLock = _isEnable;
        emit AutoIncreaseLock(_isEnable);
    }

    function setMaxBurnRate(uint256 _rate) external onlyOwner {
        // validation from 0.5-100%
        require(_rate >= 50 && _rate <= MAX, "ChamSlizStaker: OUT_OF_RANGE");
        emit SetMaxBurnRate(maxBurnRate, _rate);
        maxBurnRate = _rate;
    }

    function setMaxPegReserve(uint256 _value) external onlyOwner {
        // validation from 0.6-1
        require(
            _value >= 0.6e18 && _value <= 1e18,
            "ChamSlizStaker: OUT_OF_RANGE"
        );
        emit SetMaxPegReserve(maxPegReserve, _value);
        maxPegReserve = _value;
    }

    // Pause deposits
    function pause() public onlyManager {
        _pause();
        proxy.pause();
    }

    // Unpause deposits
    function unpause() external onlyManager {
        _unpause();
        proxy.unpause();
    }

    function grantExclusion(address account) external onlyManager {
        excluded.push(account);
        emit GrantExclusion(account);
    }

    function revokeExclusion(address account) external onlyManager {
        uint256 excludedLength = excluded.length;
        for (uint256 i = 0; i < excludedLength; i++) {
            if (excluded[i] == account) {
                excluded[i] = excluded[excludedLength - 1];
                excluded.pop();
                emit RevokeExclusion(account);
                return;
            }
        }
    }

    function circulatingSupply() public view returns (uint256) {
        uint256 excludedSupply = 0;
        uint256 excludedLength = excluded.length;
        for (uint256 i = 0; i < excludedLength; i++) {
            excludedSupply = excludedSupply + balanceOf(excluded[i]);
        }

        return totalSupply() - excludedSupply;
    }

    function calculatePenaltyFee(
        uint256 _amount
    ) public view returns (uint256) {
        uint256 pegReserve = (balanceOfWant() * MAX_RATE) / requiredReserve();
        uint256 penaltyAmount = 0;
        if (pegReserve < maxPegReserve) {
            // penaltyPercent = penaltyRate x (1 - pegReserve) * 100%
            penaltyAmount = (_amount * penaltyRate * (MAX_RATE - pegReserve)) / (MAX_RATE * MAX_RATE);
        }

        return penaltyAmount;
    }

    // Add new LP's for selling / buying fees
    function setMarketLpPairs(address _pair, bool _value) public onlyManager {
        marketLpPairs[_pair] = _value;
    }

    function setTaxSellingPercent(uint256 _value) external onlyManager returns (bool) {
		require(_value <= 100, "Max tax is 1%");
		emit SetTaxSellingPercent(taxSellingPercent, _value);
        taxSellingPercent = _value;
        return true;
    }

    function setTaxBuyingPercent(uint256 _value) external onlyManager returns (bool) {
		require(_value <= 100, "Max tax is 1%");
		emit SetTaxBuyingPercent(taxBuyingPercent, _value);
        taxBuyingPercent = _value;
        return true;
    }

    function excludeSellingTaxAddress(address _address) external onlyManager returns (bool) {
        require(!excludedSellingTaxAddresses[_address], "Address can't be excluded");
        excludedSellingTaxAddresses[_address] = true;
        return true;
    }

    function includeSellingTaxAddress(address _address) external onlyManager returns (bool) {
        require(excludedSellingTaxAddresses[_address], "Address can't be included");
        excludedSellingTaxAddresses[_address] = false;
        return true;
    }

    function excludeBuyingTaxAddress(address _address) external onlyManager returns (bool) {
        require(!excludedBuyingTaxAddresses[_address], "Address can't be excluded");
        excludedBuyingTaxAddresses[_address] = true;
        return true;
    }

    function includeBuyingTaxAddress(address _address) external onlyManager returns (bool) {
        require(excludedBuyingTaxAddresses[_address], "Address can't be included");
        excludedBuyingTaxAddresses[_address] = false;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(polWallet != address(0),"require to set polWallet address");
        address sender = _msgSender();
        
        // Selling token
		if(marketLpPairs[to] && !excludedSellingTaxAddresses[sender]) {
            if (taxSellingPercent > 0) {
                uint256 taxAmount = amount * taxSellingPercent / MAX;
                if(taxAmount > 0)
                {
                    amount = amount - taxAmount;
                    _transfer(sender, polWallet, taxAmount);
                }
            }
		}
        // Buying token
        if(marketLpPairs[sender] && !excludedBuyingTaxAddresses[to] && taxBuyingPercent > 0) {
            uint256 taxAmount = amount * taxBuyingPercent / MAX;
            if(taxAmount > 0)
            {
                amount = amount - taxAmount;
                _transfer(sender, polWallet, taxAmount);
            }
        }

        _transfer(sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        require(polWallet != address(0),"require to set polWallet address");
        
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        // Selling token
		if(marketLpPairs[to] && !excludedSellingTaxAddresses[from]) {
            if (taxSellingPercent > 0) {
                uint256 taxAmount = amount * taxSellingPercent / MAX;
                if(taxAmount > 0)
                {
                    amount = amount - taxAmount;
                    _transfer(from, polWallet, taxAmount);
                }
            }
		}
        // Buying token
        if(marketLpPairs[from] && !excludedBuyingTaxAddresses[to] && taxBuyingPercent > 0) {
            uint256 taxAmount = amount * taxBuyingPercent / MAX;
            if(taxAmount > 0)
            {
                amount = amount - taxAmount;
                _transfer(from, polWallet, taxAmount);
            }
        }

        _transfer(from, to, amount);
        return true;
    }
}

