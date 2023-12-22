// SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./BaseJumperVesting.sol";

/// @title BaseJumper presale contract
contract BaseJumperPresale is BaseJumperVesting {

    using SafeERC20 for BaseJumper;

    uint public constant PRESALE_PERCENT = 20;
    uint public constant MIN_PRESALE_AMOUNT = 0.1 ether;
    uint public constant MAX_PRESALE_AMOUNT = 0.5 ether;
    uint public constant PRESALE_CAP = 50 ether;
    uint public constant PRESALE_VESTING_PERIOD = 10 days;
    uint public totalETHDeposited;
    uint public totalWhitelisted;

    bool public hasPresaleStarted;
    bool public hasPresaleEnded;

    struct Presale {
        uint eth;
        uint withdrawn;
    }

    mapping(address => bool) public isWhitelisted;
    mapping(address => Presale) public presale;

    event Whitelisted(address[] addresses);
    event PresaleStarted();
    event PresaleEnded();
    event Buy(address user, uint purchased, uint totalPurchase);

    modifier onlyWhitelisted() {
        require(isWhitelisted[_msgSender()], "BaseJumperPresale: Only whitelisted users can call this");
        _;
    }

    constructor(address payable _baseJumper, address _treasury) BaseJumperVesting(_baseJumper, _treasury, PRESALE_PERCENT, PRESALE_VESTING_PERIOD) {}

    /// @notice Import whitelist (Owner)
    /// @param _addresses Wallet addresses
    function whitelist(address[] calldata _addresses) external onlyOwner {
        require(!hasPresaleEnded, "BaseJumperPresale: Presale has already ended");
        for (uint i; i < _addresses.length; i++) {
            isWhitelisted[_addresses[i]] = true;
        }
        totalWhitelisted += _addresses.length;
        emit Whitelisted(_addresses);
    }

    /// @notice Start presale (owner)
    function startPresale() external nonReentrant onlyOwner {
        require(!hasPresaleStarted, "BaseJumperPresale: Presale already started");
        uint total = amountToTransfer();
        baseJumper.safeTransferFrom(_msgSender(), address(this), total);
        gonTotal = baseJumper.gonBalanceOf(address(this));
        hasPresaleStarted = true;
        emit PresaleStarted();
    }

    /// @notice End presale (owner)
    function endPresale() external onlyOwner {
        require(hasPresaleStarted, "BaseJumperPresale: Presale has not started");
        require(!hasPresaleEnded, "BaseJumperPresale: Presale already ended");
        _endPresale();
    }

    /// @notice Buy tokens in presale (whitelisted users only)
    function buy() external payable nonReentrant onlyWhitelisted {
        require(hasPresaleStarted, "BaseJumperPresale: Presale has not started yet");
        require(!hasPresaleEnded, "BaseJumperPresale: Presale has ended");
        uint currentPurchase = presale[_msgSender()].eth;
        uint newPurchase = msg.value;
        uint totalPurchase = currentPurchase + newPurchase;
        require(newPurchase > 0, "BaseJumperPresale: Invalid msg.value");
        require(totalETHDeposited + newPurchase <= PRESALE_CAP, "BaseJumperPresale: Amount would exceed presale cap, enter a smaller amount");
        require(MIN_PRESALE_AMOUNT <= totalPurchase && totalPurchase <= MAX_PRESALE_AMOUNT, "BaseJumperPresale: Invalid ETH amount");
        require(totalPurchase % 0.1 ether == 0, "BaseJumperPresale: ETH amount must be an interval of 0.1 ETH");
        presale[_msgSender()].eth += newPurchase;
        totalETHDeposited += newPurchase;
        if (totalETHDeposited == PRESALE_CAP) {
            _endPresale();
        }
        payable(treasury).transfer(newPurchase);
        emit Buy(_msgSender(), newPurchase, totalPurchase);
    }

    /// @notice User presale details
    /// @param _address Address
    function userPresaleDetails(address _address) external view returns (uint total, uint withdrawn) {
        require(_address != address(0), "BaseJumper: _address cannot be the zero address");
        total = baseJumper.calculateAmount(_calculatePresaleGonValue(presale[_address].eth));
        withdrawn = baseJumper.calculateAmount(presale[_address].withdrawn);
    }

    function _endPresale() internal {
        if (totalETHDeposited < PRESALE_CAP) {
            /// @dev gonTotal is a large number therefore have to divide in brackets
            uint totalPresaleGonValue = totalETHDeposited * (gonTotal / PRESALE_CAP);
            uint unsoldPresale = gonTotal - totalPresaleGonValue;
            baseJumper.gonTransfer(treasury, unsoldPresale);
            gonTotal -= unsoldPresale;
        }
        hasPresaleEnded = true;
        emit PresaleEnded();
    }

    /// @param _eth ETH amount
    function _calculatePresaleGonValue(uint _eth) internal view returns (uint gonValue) {
        gonValue = _eth * (gonTotal / totalETHDeposited);
    }

    function _startVesting() internal view override {
        require(hasPresaleEnded, "BaseJumperPresale: Presale hasn't ended");
    }

    function _claim() internal override returns (uint gonValue) {
        Presale storage presaleUser = presale[_msgSender()];
        uint totalGonValue = _calculatePresaleGonValue(presaleUser.eth);
        gonValue = _calculateClaimableAmount(totalGonValue, presaleUser.withdrawn);
        require(gonValue > 0, "BaseJumperPresale: Already withdrawn full amount");
        gonWithdrawn += gonValue;
        presaleUser.withdrawn += gonValue;
    }

    function _availableToClaim(address _address) internal override view returns (uint gonValue) {
        uint total = _calculatePresaleGonValue(presale[_address].eth);
        uint withdrawn = presale[_address].withdrawn;
        gonValue = _calculateClaimableAmount(total, withdrawn);
    }

    function _hasVestment(address _address) internal view override returns (bool) {
        return presale[_address].eth > 0;
    }
}

