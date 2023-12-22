// SPDX-License-Identifier: Unlicense
pragma solidity = 0.8.17;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./BaseJumper.sol";

/// @title BaseJumper presale contract
contract BaseJumperPresale is Ownable, ReentrancyGuard {

    using SafeERC20 for BaseJumper;

    BaseJumper public immutable baseJumper;
    address payable public immutable treasury;
    uint public constant PERCENT_DENOMINATOR = 100;
    uint public constant PRESALE_PERCENT = 30;
    uint public constant MIN_PRESALE_AMOUNT = 0.1 ether;
    uint public constant MAX_PRESALE_AMOUNT = 0.5 ether;
    uint public constant PRESALE_CAP = 50 ether;
    uint public constant BATCH_SIZE = 100;
    uint public gonTotal;
    uint public totalETHDeposited;
    uint public totalWhitelisted;

    bool public hasPresaleStarted;
    bool public hasPresaleEnded;
    uint public totalPresalers;

    uint public lastBatch;

    struct Presale {
        uint id;
        uint eth;
    }

    mapping(address => bool) public isWhitelisted;
    mapping(address => Presale) public presale;
    mapping(uint => address) public presaleIndex;

    event Whitelisted(address[] addresses);
    event PresaleStarted();
    event PresaleEnded();
    event Buy(address user, uint purchased, uint totalPurchase);
    event BulkTransfer();

    modifier onlyWhitelisted() {
        require(isWhitelisted[_msgSender()], "BaseJumperPresale: Only whitelisted users can call this");
        _;
    }

    constructor(address payable _baseJumper, address payable _treasury) {
        require(_baseJumper != address(0), "BaseJumperPresale: _baseJumper cannot be the zero address");
        require(_treasury != address(0), "BaseJumperPresale: _treasury cannot be the zero address");
        baseJumper = BaseJumper(_baseJumper);
        treasury = _treasury;
    }

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
        hasPresaleStarted = true;
        baseJumper.safeTransferFrom(_msgSender(), address(this), total);
        gonTotal = baseJumper.gonBalanceOf(address(this));
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
        if (currentPurchase == 0) {
            totalPresalers++;
            presaleIndex[totalPresalers] = _msgSender();
        }
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
        treasury.transfer(newPurchase);
        emit Buy(_msgSender(), newPurchase, totalPurchase);
    }

    /// @notice Amount to transfer
    /// @return total - Total amount
    function amountToTransfer() public view returns (uint total) {
        total = baseJumper.totalSupply() * PRESALE_PERCENT / PERCENT_DENOMINATOR;
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

    /// @notice Total batches (used after presale has ended)
    /// @return total Total batches
    function totalBatches() public view returns (uint total) {
        require(hasPresaleEnded, "BaseJumperPresale: Presale has not ended");
        uint remainder = totalPresalers % BATCH_SIZE;
        total = totalPresalers / BATCH_SIZE;
        if(remainder > 0) {
            total += 1;
        }
        return total;
    }

    /// @notice Bulk transfer presalers their tokens (owner)
    /// @param _batch Batch number
    function bulkTransfer(uint _batch) external nonReentrant onlyOwner {
        require(hasPresaleEnded, "BaseJumperPresale: Presale has not ended");
        require(lastBatch + 1 == _batch && _batch <= totalBatches(), "BaseJumperPresale: Invalid batch number");
        uint startIndex = (lastBatch * BATCH_SIZE);
        uint endIndex = startIndex + BATCH_SIZE;
        if (endIndex > totalPresalers) {
            endIndex = totalPresalers;
        }
        for (uint i = startIndex; i < endIndex; i++) {
            address user = presaleIndex[i + 1];
            uint gonValue = _calculatePresaleGonValue(user);
            baseJumper.gonTransfer(user, gonValue);
        }
        lastBatch = _batch;
        emit BulkTransfer();
    }

    /// @param _user User address
    function _calculatePresaleGonValue(address _user) internal view returns (uint gonValue) {
        gonValue = presale[_user].eth * (gonTotal / totalETHDeposited);
    }
}

