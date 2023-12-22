// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import necessary ERC20 interfaces
import "./IERC20.sol";

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";

contract NOXTokenSale is OwnableUpgradeable {
    // Token details
    IERC20 public USDT;
    IERC20 public USDC;

    uint public DecimalUSDT;
    uint public DecimalUSDC;

    uint256 public startTime;

    bool public isStop;

    struct Allocations {
        uint256 allocatedAmount;
        uint256 remainingAmount;
    }

    // Whitelisted users
    mapping(address => Allocations) public whitelistAmounts;

    uint256 public noxPerUsd;

    uint256 public noxValue;

    address public feeRecivingWallet;

    mapping(address => bool) public isTeam;
    // Event to emit on token purchase
    event TokensPurchased(
        address indexed buyer,
        uint256 usdtAmount,
        uint256 usdcAmount,
        uint256 noxAmount
    );

    // Modifier to restrict access to whitelisted users only
    modifier onlyWhitelisted() {
        require(
            whitelistAmounts[msg.sender].allocatedAmount != 0,
            "Not whitelisted"
        );
        _;
    }
    modifier onlyTeam() {
        require(isTeam[msg.sender], "Only Team Member can call this function");
        _;
    }

    // Constructor to set token addresses and initialize whitelisted users
    function initialize(
        address _usdtAddress,
        address _usdcAddress,
        uint _DecimalUSDT,
        uint _DecimalUSDC,
        uint256 _startTime
    ) public initializer {
        __Ownable_init();
        USDT = IERC20(_usdtAddress);
        USDC = IERC20(_usdcAddress);

        noxPerUsd = 142857 * 10 ** 5;

        startTime = _startTime;
        DecimalUSDT = _DecimalUSDT;
        DecimalUSDC = _DecimalUSDC;
    }

    // Function to allow users to purchase NOX tokens
    function purchaseTokens(
        uint256 usdtAmount,
        uint256 usdcAmount
    ) external onlyWhitelisted {
        require(!isStop, "Pre sale ended");
        // Perform necessary calculations to determine NOX tokens to be minted
        uint256 noxAmount = calculateNOXAmount(usdtAmount, usdcAmount);

        require(
            whitelistAmounts[msg.sender].remainingAmount >= noxAmount,
            "Allocation Exceeded"
        );

        whitelistAmounts[msg.sender].remainingAmount -= noxAmount;

        // Transfer USDT and USDC from user to owner
        if (usdtAmount > 0)
            USDT.transferFrom(msg.sender, feeRecivingWallet, usdtAmount);
        if (usdcAmount > 0)
            USDC.transferFrom(msg.sender, feeRecivingWallet, usdcAmount);

        // Emit purchase event
        emit TokensPurchased(msg.sender, usdtAmount, usdcAmount, noxAmount);
    }

    // Function to calculate the amount of NOX tokens to mint based on the purchased USDT and USDC
    function calculateNOXAmount(
        uint256 usdtAmount,
        uint256 usdcAmount
    ) internal view returns (uint256) {
        uint256 noxForUSDT = (usdtAmount * noxPerUsd) / 10 ** DecimalUSDT;
        uint256 noxForUSDC = (usdcAmount * noxPerUsd) / 10 ** DecimalUSDC;

        uint256 noxAmount = noxForUSDT + noxForUSDC;

        return noxAmount;
    }

    // Function to add or remove users from the whitelist (only callable by owner)
    function updateWhitelist(
        address[] memory _users,
        uint256[] memory _amounts
    ) external onlyTeam {
        require(_users.length == _amounts.length, "Invalid array combination");
        for (uint i = 0; i < _users.length; i++) {
            whitelistAmounts[_users[i]].allocatedAmount = _amounts[i];
            whitelistAmounts[_users[i]].remainingAmount = _amounts[i];
        }
    }

    function changeNoxValue(uint256 _noxPerUSD) external onlyTeam {
        noxPerUsd = _noxPerUSD;
    }

    function changeStableCoins(address _usdt, address _usdc) external onlyTeam {
        USDT = IERC20(_usdt);
        USDC = IERC20(_usdc);
    }

    function changeDecimals(uint _usdt, uint _usdc) external onlyTeam {
        DecimalUSDT = _usdt;
        DecimalUSDC = _usdc;
    }

    function addTeamMemers(address _wallet, bool _status) external onlyOwner {
        isTeam[_wallet] = _status;
    }

    function changeFeeRecivingWallet(address _wallet) external onlyOwner {
        feeRecivingWallet = _wallet;
    }

    function stopThePreSale() external onlyOwner {
        isStop = true;
    }
}

