pragma solidity ^0.5.16;

import "./Ownable.sol";
import "./ApolloxSafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol";

pragma experimental ABIEncoderV2;

contract ApolloxTradingReward is Ownable, ReentrancyGuard {
    using ApolloxSafeMath for uint;
    using SafeERC20 for IERC20;

    event ReceiveBNB(uint amount);
    event Claimed(uint256 indexed id, address indexed to, bool isETH, address currency, uint256 amount, uint256 reservedAmount, uint256 deadline);
    event TransferToCounterParty(bool isETH, address currency, uint256 amount);
    event Paused();
    event Unpaused();
    event NewTruthHolder(address oldTruthHolder, address newTruthHolder);
    event NewOperator(address oldOperator, address newOperator);
    event NewTreasuryAddress(address oldTreasuryAddress, address newTreasuryAddress);
    event NewTaxAddress(address oldTaxAddress, address newTaxAddress);
    event AddCurrency(address indexed currency);
    event RemoveCurrency(address indexed currency);

    bool public paused;
    address public truthHolder;
    address public operator;
    address payable public taxAddress;
    address payable public treasuryAddress;
    mapping(address => bool) public supportCurrency;
    mapping(uint => uint) public claimHistory;

    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "only operator can call");
        _;
    }

    constructor (address truthHolder_, address operator_, address payable taxAddress_, address payable treasuryAddress_) ReentrancyGuard() public {
        paused = false;
        truthHolder = truthHolder_;
        operator = operator_;
        taxAddress = taxAddress_;
        treasuryAddress = treasuryAddress_;
    }

    function() external payable {
        if (msg.value > 0) {
            emit ReceiveBNB(msg.value);
        }
    }

    function _transfer(address payable to, bool isBNB, address currency, uint amount, uint reservedAmount) internal {
        if (isBNB) {
            require(address(this).balance >= amount, "not enough BNB balance");
            require(to.send(amount), "BNB transfer failed");
        } else {
            IERC20 token = IERC20(currency);
            uint balance = token.balanceOf(address(this));
            uint totalAmount = amount.add(reservedAmount);
            require(balance >= totalAmount, "not enough currency balance");
            token.safeTransfer(to, amount);
            if (reservedAmount > 0) {
                token.safeTransfer(taxAddress, reservedAmount);
            }
        }
    }

    function transferToTreasury(bool isBNB, address currency, uint amount) external onlyOperator nonReentrant {
        _transfer(treasuryAddress, isBNB, currency, amount, 0);
        emit TransferToCounterParty(isBNB, currency, amount);
    }

    function claim(bytes calldata message, bytes calldata signature) external notPaused nonReentrant {
        address source = source(message, signature);
        require(source == truthHolder, "only accept truthHolder signed message");

        (uint256 id, address payable to, bool isBNB, address currency, uint256 amount, uint256 reservedAmount, uint256 deadline) = abi.decode(message, (uint256, address, bool, address, uint256, uint256, uint256));
        require(claimHistory[id] == 0, "already claimed");
        require(amount > 0, "Claim amount is zero");
        require(isBNB || supportCurrency[currency], "currency not support");
        require(block.timestamp < deadline, "already passed deadline");

        claimHistory[id] = block.number;
        _transfer(to, isBNB, currency, amount, reservedAmount);
        emit Claimed(id, to, isBNB, currency, amount, reservedAmount, deadline);
    }

    function source(bytes memory message, bytes memory signature) public pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(message)));
        return ECDSA.recover(hash, signature);
    }

    function _pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function _unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function _changeTruthHolder(address newTruthHolder) external onlyOwner {
        require(newTruthHolder != address(0), "New truth holder is zero address");

        address oldHolder = truthHolder;
        truthHolder = newTruthHolder;
        emit NewTruthHolder(oldHolder, newTruthHolder);
    }

    function _setOperator(address newOperator) external onlyOwner {
        require(newOperator != address(0), "New operator is zero address");

        address oldOperator = operator;
        operator = newOperator;
        emit NewOperator(oldOperator, newOperator);
    }

    function _setTreasuryAddress(address payable newTreasuryAddress) external onlyOwner {
        require(newTreasuryAddress != address(0), "New treasury address is zero address");

        address payable oldTreasuryAddress = treasuryAddress;
        treasuryAddress = newTreasuryAddress;
        emit NewTreasuryAddress(oldTreasuryAddress, newTreasuryAddress);
    }

    function _setTaxAddress(address payable newTaxAddress) external onlyOwner {
        require(newTaxAddress != address(0), "New tax address is zero address");

        address payable oldTaxAddress = taxAddress;
        taxAddress = newTaxAddress;
        emit NewTaxAddress(oldTaxAddress, newTaxAddress);
    }

    function _addCurrency(address currency) external onlyOwner {
        supportCurrency[currency] = true;
        emit AddCurrency(currency);
    }

    function _removeCurrency(address currency) external onlyOwner {
        delete supportCurrency[currency];
        emit RemoveCurrency(currency);
    }

}

