// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

import "./IVault.sol";

contract OtcRebalancer is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public weth;
    IVault public vault;

    address public token;
    address public counterParty;

    uint256 public lifetimeLimit;
    uint256 public processed;
    uint256 public tokenEthPrice;
    bool private priceSet;
    bool private limitSet;
    bool private tokenSet;

    event Initialized(address indexed vault, address indexed token);
    event SetVault(address indexed vault);
    event SetToken(address indexed token);
    event SetEthTokenPrice(uint256 indexed price);
    event DepositEth(uint256 indexed amount);
    event DepositToken(address indexed from, uint256 indexed amount);
    event WithdrawEth(uint256 indexed amount);
    event WithdrawToken(address indexed to, uint256 indexed amount);
    event Swap(uint256 indexed ethAmount, uint256 indexed tokenAmount);
    event SetLifetimeLimit(uint256 indexed limit);

    constructor() {
        _disableInitializers();
    }

    modifier onlyVault()  {
        require(_msgSender() == address(vault), "Only permitted for vault");
        _;
    }

    modifier onlyCounterParty() {
        require(_msgSender() == counterParty, "Only permitted for counterParty");
        _;
    }

    function init(IVault _vault, address _token) external initializer {
        require(address(_vault) != address(0), "Invalid vault address");
        require(_token != address(0), "Invalid token address");

        __Ownable_init();
        vault = _vault;
        token = _token;
        priceSet = false;

        emit Initialized(address(vault), token);
    }

    receive() external payable onlyVault {
        require(msg.value + processed <= lifetimeLimit, "Eth deposit lifttime limit reached");

        processed += msg.value;
        emit DepositEth(msg.value);
    }

    /// @notice Set vault
    /// @param _vault vault address
    function setVault(IVault _vault) external onlyOwner {
        require(address(_vault) != address(0), "Invalid vault address");

        vault = _vault;
        emit SetVault(address(vault));
    }

    /// @notice Set token
    /// @param _token token address
    function setToken(address _token) external onlyOwner {
        require(!tokenSet, "Token already set");
        require(_token != address(0), "Invalid token address");

        token = _token;
        tokenSet = true;
        emit SetToken(token);
    }

    function setLifeTimeLimit(uint256 _limit) external onlyOwner {
        require(!limitSet, "Limit already set");
        require(_limit != 0, "Invalid limit value");

        lifetimeLimit = _limit;
        limitSet = true;
        emit SetLifetimeLimit(_limit);
    }

    function setEthTokenPrice(uint256 _price) external onlyOwner {
        require(!priceSet, "Price already set");
        require(_price != 0, "Invalid token price");

        tokenEthPrice = _price;
        priceSet = true;
        emit SetEthTokenPrice(_price);
    }

    function depositToken(uint256 _amount) external onlyCounterParty {
        require(IERC20(token).balanceOf(_msgSender()) >= _amount, "Insufficient token balance");
        require(IERC20(token).allowance(_msgSender(), address(this)) >= _amount, "Insufficient token allowance");
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _amount);

        emit DepositToken(_msgSender(), _amount);
    }

    function withdrawEth(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient amount to withdraw");
        (bool success, ) = address(vault).call{value: _amount}("");

        require(success, "Eth withdraw failed");
        emit WithdrawEth(_amount);
    }

    function withdrawToken(uint256 _amount) external onlyCounterParty {
        require(IERC20(token).balanceOf(address(this)) >= _amount, "Insufficient amount to withdraw");
        IERC20(token).safeTransfer(_msgSender(), _amount);

        emit WithdrawToken(_msgSender(), _amount);
    }

    function execute() external onlyOwner {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        require(tokenBalance > 0, "Insufficient token amount to swap");
        require(address(this).balance > 0, "Insufficient eth amount to swap");

        uint256 swapEthAmount = tokenEthPrice * tokenBalance / 10**ERC20(token).decimals();
        if (swapEthAmount <= address(this).balance) {
            IERC20(token).safeTransfer(address(vault), tokenBalance);
            (bool success, ) = counterParty.call{value: swapEthAmount}("");
            require(success, "Swap failed");
            emit Swap(swapEthAmount, tokenBalance);
        } else {
            uint256 swapTokenAmount = address(this).balance * 10**ERC20(token).decimals() / tokenEthPrice;
            require(swapTokenAmount < tokenBalance, "Swap amount calculation failed");
            IERC20(token).safeTransfer(address(vault), swapTokenAmount);
            (bool success, ) = counterParty.call{value: address(this).balance}("");
            require(success, "Swap failed");
            emit Swap(address(this).balance, swapTokenAmount);
        }
    }
}
