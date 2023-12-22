// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./Pausable.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./PRBMathUD60x18.sol";
import "./EnumerableSet.sol";

import {IAssetManager} from "./IAssetManager.sol";
import {IBalanceSheet} from "./IBalanceSheet.sol";
import {IUnderwritingLiquidityPool} from "./IUnderwritingLiquidityPool.sol";

//   /$$$$$$$            /$$$$$$$$
//  | $$__  $$          | $$_____/
//  | $$  \ $$  /$$$$$$ | $$     /$$$$$$  /$$$$$$   /$$$$$$
//  | $$  | $$ /$$__  $$| $$$$$ /$$__  $$|____  $$ /$$__  $$
//  | $$  | $$| $$$$$$$$| $$__/| $$  \__/ /$$$$$$$| $$  \ $$
//  | $$  | $$| $$_____/| $$   | $$      /$$__  $$| $$  | $$
//  | $$$$$$$/|  $$$$$$$| $$   | $$     |  $$$$$$$|  $$$$$$$
//  |_______/  \_______/|__/   |__/      \_______/ \____  $$
//                                                 /$$  \ $$
//                                                |  $$$$$$/
//                                                 \______/

/// @title UnderwritingLiquidityPool takes in ERC20 tokens and mints ERC20 LP wrapper tokens to keep track of Users position
/// @author DeFragDAO
/// @custom:experimental This is an experimental contract
contract UnderwritingLiquidityPool is
    IUnderwritingLiquidityPool,
    ERC20,
    ReentrancyGuard,
    Pausable,
    AccessControl
{
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable liquidityToken;
    address public immutable assetManager;
    address public immutable balanceSheet;

    uint256 public constant INITIAL_EXCHANGE_RATE = 1e6;

    bytes32 public constant DEFRAG_SYSTEM_ADMIN_ROLE =
        keccak256("DEFRAG_SYSTEM_ADMIN_ROLE");

    EnumerableSet.AddressSet private depositors;
    mapping(address => uint256) private depositorToTotalDepositedAmount;
    mapping(address => uint256) private depositorToTotalMintedAmount;
    mapping(address => uint256) private depositorToTotalRedeemedAmount;
    mapping(address => uint256) private depositorToTotalWithdrawnAmount;

    event Deposited(
        address indexed _user,
        uint256 _amount,
        uint256 _exchangeRate
    );
    event Minted(address indexed _user, uint256 _amount, uint256 _exchangeRate);
    event Redeemed(
        address indexed _user,
        uint256 _amount,
        uint256 _exchangeRate
    );
    event Withdrawn(
        address indexed _user,
        uint256 _amount,
        uint256 _exchangeRate
    );
    event DepositorAdded(address indexed _user);

    using PRBMathUD60x18 for uint256;

    constructor(
        address _liquidityToken,
        address _assetManager,
        address _balanceSheet
    ) ERC20("Underwriting Liquidity Pool", "SmolUSDC") {
        liquidityToken = _liquidityToken;
        assetManager = _assetManager;
        balanceSheet = _balanceSheet;

        _pause();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Returns the exchange rate of the Underwriting Liquidity Pool
     * @return uint256 The exchange rate
     */
    function exchangeRate() public view returns (uint256) {
        // (Asset Manager USDC Balance + outstanding loans) / Total Minted Supply
        // IERC20(liquidityToken).balanceOf(address(AssetManager))
        // BalanceSheet.getTotalOutstandingLoans()
        // totalSupply()

        if (totalSupply() == 0) return INITIAL_EXCHANGE_RATE;

        return
            unpaddedAmount(
                paddedAmount(IERC20(liquidityToken).balanceOf(assetManager)) +
                    IBalanceSheet(balanceSheet).getTotalOutstandingLoans()
            ).div((paddedAmount(totalSupply())));
    }

    /**
     * @notice Deposits ERC20 tokens into the Underwriting Liquidity Pool
     * receive back a wrap token which represents your position in the pool
     * @param _amount The amount of ERC20 tokens to deposit
     */
    function deposit(uint256 _amount) public nonReentrant whenNotPaused {
        // solhint-disable-next-line reason-string
        require(
            _amount > 0,
            "UnderwritingLiquidityPool: Amount must be greater than 0"
        );
        uint256 currentExchangeRate = exchangeRate();
        uint256 amountToMint = mintAmount(_amount);

        IERC20(liquidityToken).transferFrom(msg.sender, assetManager, _amount);
        _mint(msg.sender, amountToMint);

        if (!isExistingDepositor(msg.sender)) {
            _addUser(msg.sender);
        }

        depositorToTotalDepositedAmount[msg.sender] += _amount;
        depositorToTotalMintedAmount[msg.sender] += amountToMint;

        emit Deposited(msg.sender, _amount, currentExchangeRate);
        emit Minted(msg.sender, amountToMint, currentExchangeRate);
    }

    /**
     * @notice Redeems ERC20 tokens from the Underwriting Liquidity Pool
     * burn the wrapped token and receive the deposited ERC20 tokens - USDC
     * @param _amount The amount of ERC20 tokens to redeem
     */
    function redeem(uint256 _amount) public nonReentrant whenNotPaused {
        // solhint-disable-next-line reason-string
        require(
            _amount > 0,
            "UnderwritingLiquidityPool: Amount must be greater than 0"
        );
        uint256 currentExchangeRate = exchangeRate();
        uint256 amountToWithdraw = withdrawAmount(_amount);

        _burn(msg.sender, _amount);
        IAssetManager(assetManager).redeemERC20(msg.sender, amountToWithdraw);

        depositorToTotalRedeemedAmount[msg.sender] += _amount;
        depositorToTotalWithdrawnAmount[msg.sender] += amountToWithdraw;

        emit Redeemed(msg.sender, _amount, currentExchangeRate);
        emit Withdrawn(msg.sender, amountToWithdraw, currentExchangeRate);
    }

    /**
     * @notice Returns the amount of ERC20 tokens that will be minted for a given amount of ERC20 tokens
     * @param _amount The amount of ERC20 tokens to be deposited
     * @return uint256 The amount of ERC20 tokens that will be minted
     */
    function mintAmount(uint256 _amount) public view returns (uint256) {
        return _amount.div(paddedAmount(exchangeRate()));
    }

    /**
     * @notice Returns the amount of ERC20 tokens that will be redeemed for a given amount of wrapped tokens
     * @param _amount The amount of wrapped ERC20 tokens to be burned
     * @return uint256 The amount of USDC ERC20 tokens that will be redeemed
     */
    function withdrawAmount(uint256 _amount) public view returns (uint256) {
        return _amount.mul(paddedAmount(exchangeRate()));
    }

    /**
     * @notice checks if user address exists
     * @param _userAddress - address of the user
     * @return bool - true or false
     */
    function isExistingDepositor(
        address _userAddress
    ) public view returns (bool) {
        return EnumerableSet.contains(depositors, _userAddress);
    }

    /**
     * @notice gets all depositors
     * @return array of all depositors
     */
    function getAllDepositors() public view returns (address[] memory) {
        return EnumerableSet.values(depositors);
    }

    /**
     * @notice gets total deposited amount for a user
     * @param _userAddress - address of the user
     * @return total deposited amount
     */
    function getDepositedAmount(
        address _userAddress
    ) public view returns (uint256) {
        return depositorToTotalDepositedAmount[_userAddress];
    }

    /**
     * @notice gets total minted amount for a user
     * @param _userAddress - address of the user
     * @return total minted amount
     */
    function getMintedAmount(
        address _userAddress
    ) public view returns (uint256) {
        return depositorToTotalMintedAmount[_userAddress];
    }

    /**
     * @notice gets total redeemed amount for a user
     * @param _userAddress - address of the user
     * @return total redeemed amount
     */
    function getRedeemedAmount(
        address _userAddress
    ) public view returns (uint256) {
        return depositorToTotalRedeemedAmount[_userAddress];
    }

    /**
     * @notice gets total withdrawn amount for a user
     * @param _userAddress - address of the user
     * @return total withdrawn amount
     */
    function getWithdrawnAmount(
        address _userAddress
    ) public view returns (uint256) {
        return depositorToTotalWithdrawnAmount[_userAddress];
    }

    /**
     * @notice gets total deposited amount for all users
     * @return total deposited amount
     */
    function getTotalDepositedAmount() public view returns (uint256) {
        uint256 totalDepositedAmount = 0;
        address[] memory allDepositors = getAllDepositors();
        for (uint256 i = 0; i < allDepositors.length; i++) {
            totalDepositedAmount += getDepositedAmount(allDepositors[i]);
        }
        return totalDepositedAmount;
    }

    /**
     * @notice gets total minted amount for all users
     * @return total minted amount
     */
    function getTotalMintedAmount() public view returns (uint256) {
        uint256 totalMintedAmount = 0;
        address[] memory allDepositors = getAllDepositors();
        for (uint256 i = 0; i < allDepositors.length; i++) {
            totalMintedAmount += getMintedAmount(allDepositors[i]);
        }
        return totalMintedAmount;
    }

    /**
     * @notice gets total redeemed amount for all users
     * @return total redeemed amount
     */
    function getTotalRedeemedAmount() public view returns (uint256) {
        uint256 totalRedeemedAmount = 0;
        address[] memory allDepositors = getAllDepositors();
        for (uint256 i = 0; i < allDepositors.length; i++) {
            totalRedeemedAmount += getRedeemedAmount(allDepositors[i]);
        }
        return totalRedeemedAmount;
    }

    /**
     * @notice gets total withdrawn amount for all users
     * @return total withdrawn amount
     */
    function getTotalWithdrawnAmount() public view returns (uint256) {
        uint256 totalWithdrawnAmount = 0;
        address[] memory allDepositors = getAllDepositors();
        for (uint256 i = 0; i < allDepositors.length; i++) {
            totalWithdrawnAmount += getWithdrawnAmount(allDepositors[i]);
        }
        return totalWithdrawnAmount;
    }

    function getPosition(
        address _userAddress
    )
        public
        view
        returns (
            uint256 totalDepositedAmount,
            uint256 totalMintedAmount,
            uint256 totalRedeemedAmount,
            uint256 totalWithdrawnAmount
        )
    {
        return (
            depositorToTotalDepositedAmount[_userAddress],
            depositorToTotalMintedAmount[_userAddress],
            depositorToTotalRedeemedAmount[_userAddress],
            depositorToTotalWithdrawnAmount[_userAddress]
        );
    }

    /**
     * @notice Returns the decimals of the wrapped ERC20
     * @return Returns the decimals of the wrapped ERC20
     */
    function decimals()
        public
        view
        virtual
        override(ERC20, IERC20Metadata)
        returns (uint8)
    {
        return IERC20Metadata(liquidityToken).decimals();
    }

    /**
     * @notice Returns the padded amount - 18 decimals
     * @param _amount The amount of ERC20 tokens
     * @return uint256 The padded amount of ERC20 tokens
     */
    function paddedAmount(uint256 _amount) public view returns (uint256) {
        return (_amount * 10 ** (18 - decimals()));
    }

    /**
     * @notice Returns the unpadded amount - 6 decimals
     * @param _amount The amount of ERC20 tokens
     * @return uint256 The unpadded amount of ERC20 tokens
     */
    function unpaddedAmount(uint256 _amount) public view returns (uint256) {
        return (_amount / 10 ** (18 - decimals()));
    }

    /**
     * @notice pause borrowing
     */
    function pause() public onlyAdmin {
        _pause();
    }

    /**
     * @notice unpause borrowing
     */
    function unpause() public onlyAdmin {
        _unpause();
    }

    /**
     * @notice modifier to restrict access to only admin
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFRAG_SYSTEM_ADMIN_ROLE, msg.sender),
            "AssetManager: only DefragSystemAdmin"
        );
        _;
    }

    /**
     * @dev private function - called by deposit function
     * @notice adds user to a users enumerable set
     * @param _userAddress - address of the user
     */
    function _addUser(address _userAddress) private {
        depositors.add(_userAddress);
        emit DepositorAdded(_userAddress);
    }
}

