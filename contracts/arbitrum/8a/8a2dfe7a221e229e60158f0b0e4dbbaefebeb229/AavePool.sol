// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./SafeMath.sol";
import "./console.sol";

import "./AddressesArbitrum.sol";
import "./AbstractLendingPool.sol";
import "./IProtocolPool.sol";

import "./IRouter.sol";

/// @custom:todo add pausable
/// @custom:todo add modifier checks for token addresses
/// @custom:todo add access controls
contract AavePool is AbstractLendingPool {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSet for EnumerableSet.AddressSet;

    //  Core Variables
    address private protocolPoolAddress;

    IProtocolPool private pool;
    EnumerableSet.AddressSet private tokenAddresses;

    //  ============================================================
    //  Initialisation
    //  ============================================================
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _poolAddress, address[] memory _tokens, address newOwner) public initializer {
        __Ownable_init();
        __Pausable_init();
        initialisePool(_poolAddress);
        addTokenAddresses(_tokens);
        transferOwnership(newOwner);
    }

    // ==============================================================================================
    /// Query Functions
    // ==============================================================================================
    /// @notice Returns a set of ADDRESSES of the erc20 tokens that are managed by the vault
    function getPoolTokens() external view override returns (address[] memory) {
        return tokenAddresses.values();
    }

    /// @notice Returns true if the token is managed
    function isPoolToken(address token) external view override returns (bool) {
        return tokenAddresses.contains(token);
    }

    /// @notice Returns the tokens managed and amounts of each token managed
    function getPoolTokensValue()
        external
        view
        override
        returns (address[] memory, uint256[] memory)
    {
        return _getPoolTokensValue();
    }

    function _getPoolTokensValue()
        internal
        view
        returns (address[] memory, uint256[] memory)
    {
        address[] memory addresses = tokenAddresses.values();
        uint256[] memory tokenValues = new uint256[](addresses.length);

        for (uint index = 0; index < addresses.length; index++) {
            tokenValues[index] = IERC20Upgradeable(addresses[index]).balanceOf(address(this));
        }

        return (addresses, tokenValues);
    }

    // ==============================================================================================
    /// Contract Management Functions
    // ==============================================================================================
    function initialisePool(address _protocolPoolAddress) private {
        protocolPoolAddress = _protocolPoolAddress;
        pool = IProtocolPool(protocolPoolAddress);
    }

    /// @notice Clears the token addresses
    /// @dev note that this will not clear the underlying tokens
    function clearTokenAddress() external onlyOwner whenNotPaused {
        for (uint index = 0; index < tokenAddresses.length(); index++) {
            tokenAddresses.remove(tokenAddresses.at(index));
        }
    }

    /// @notice Clears the token addresses
    /// @dev note that this will not clear the underlying tokens
    function addTokenAddresses(address[] memory _tokens) private {
        for (uint index = 0; index < _tokens.length; index++) {
            tokenAddresses.add(_tokens[index]);
        }
    }

    // ==============================================================================================
    /// Transactional Functions
    // ==============================================================================================
    /// @notice withdraws all assets to owner
    function withdrawAll()
        external
        onlyOwner
        whenNotPaused
        returns (address[] memory tokens, uint256[] memory actualTokenAmounts)
    {
        address[] memory _tokens = tokenAddresses.values();
        uint256[] memory _actualTokenAmounts;

        for (uint index = 0; index < _tokens.length; ++index) {
          if (IERC20Upgradeable(_tokens[index]).balanceOf(address(this)) > 0) {
            // Transfers the withdrawal amount back to the owner
            IERC20Upgradeable(_tokens[index]).safeIncreaseAllowance(
                owner(),
                IERC20Upgradeable(_tokens[index]).balanceOf(address(this))
            );
            IERC20Upgradeable(_tokens[index]).transfer(owner(), IERC20Upgradeable(_tokens[index]).balanceOf(address(this)));
          }
        }

        return (
          _tokens,
          _actualTokenAmounts
        );
    }

    // ==============================================================================================
    /// Protocol Query Functions
    // ==============================================================================================
    /// @notice refer to https://docs.aave.com/developers/core-contracts/pool#getuseraccountdata
    /// @return uint256 totalCollateralBase
    /// @return uint256 totalDebtBase
    /// @return uint256 availableBorrowBase
    /// @return uint256 currentLiquidiationThreshold
    /// @return uint256 loanToValue
    /// @return uint256 healthFactor
    function getAccountData()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256)
    {
        return pool.getUserAccountData(address(this));
    }

    /// @dev Function is currently experimental and should not be used in production.
    function _getReservesList() external view returns (address[] memory) {
        return pool.getReservesList();
    }

    // ==============================================================================================
    /// Protocol Transactional Functions
    // ==============================================================================================
    /// @notice supply collateral to the lending pool
    function supply(
        address assetAddress,
        uint256 amount
    ) external override onlyOwner whenNotPaused {
        // Approve Aave pool to access amount from this contract
        IERC20Upgradeable(assetAddress).safeIncreaseAllowance(protocolPoolAddress, amount);

        try pool.supply(assetAddress, amount, address(this), 0) {
            /// Emits supply event when transaction completes
            emit Supply(assetAddress, address(this), amount);
        } catch Error(string memory _err) {
            console.log("Error");
            console.log(_err);
        }
    }

    /// @notice withdraws from the lending pool
    function withdraw(
        address assetAddress,
        uint256 amount
    ) external override onlyOwner whenNotPaused returns (uint256) {
        // if the amount is zero, we will try to withdraw everything
        if (amount == 0) {
            amount = type(uint).max;
        }

        // Approve Aave pool to access amount from this contract
        IERC20Upgradeable(assetAddress).safeIncreaseAllowance(protocolPoolAddress, amount);

        try pool.withdraw(assetAddress, type(uint).max, address(this)) {
            // Transfers the withdrawal amount back to the owner
            uint256 actualTokenAmount = IERC20Upgradeable(assetAddress).balanceOf(address(this));
            IERC20Upgradeable(assetAddress).safeIncreaseAllowance(owner(), actualTokenAmount);
            IERC20Upgradeable(assetAddress).transfer(owner(), actualTokenAmount);
            emit Withdraw(assetAddress, owner(), actualTokenAmount);
            return actualTokenAmount;
        } catch Error(string memory _err) {
            console.log("Withdraw Error");
            console.log(_err);
            return 0;
        }
    }

    /// @notice borrows from the lending pool and transfer
    function borrowAndTransfer(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode,
        address recipientAddress
    ) external override onlyOwner whenNotPaused {
        _borrow(assetAddress, amount, interestRateMode);
        IERC20Upgradeable(assetAddress).safeIncreaseAllowance(recipientAddress, amount);
        IERC20Upgradeable(assetAddress).transfer(recipientAddress, amount);
    }

    /// @notice borrows from the lending pool
    function borrow(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) external override onlyOwner whenNotPaused {
        _borrow(assetAddress, amount, interestRateMode);
    }

    function _borrow(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) internal whenNotPaused {
        // Approve Aave pool to access amount from this contract
        IERC20Upgradeable(assetAddress).safeIncreaseAllowance(protocolPoolAddress, amount);

        try
            pool.borrow(
                assetAddress,
                amount,
                interestRateMode,
                0,
                address(this)
            )
        {
            emit Borrow(assetAddress, address(this), amount, interestRateMode);
        } catch Error(string memory _err) {
            console.log("Borrow Error");
            console.log(_err);
        }
    }

    /// @notice repays the lending pool
    function repay(
        address assetAddress,
        uint256 amount,
        uint256 interestRateMode
    ) external override onlyOwner whenNotPaused returns (uint256) {
        // Approve Aave pool to access amount from this contract
        IERC20Upgradeable(assetAddress).safeIncreaseAllowance(protocolPoolAddress, amount);

        try pool.repay(assetAddress, amount, interestRateMode, address(this)) {
            emit Repay(assetAddress, address(this), amount);

            // @todo move to a separate exchange contract
            if (IERC20Upgradeable(assetAddress).balanceOf(address(this)) > 0) {
                IERC20Upgradeable(assetAddress).safeIncreaseAllowance(
                    Addresses.GMX_ROUTER,
                    IERC20Upgradeable(assetAddress).balanceOf(address(this))
                );
                address[] memory inOutAddresses = new address[](2);
                inOutAddresses[0] = assetAddress;
                inOutAddresses[1] = Addresses.USDC_ADDRESS;
                IRouter(Addresses.GMX_ROUTER).swap(
                    inOutAddresses,
                    IERC20Upgradeable(assetAddress).balanceOf(address(this)),
                    0,
                    address(this)
                );
            }

            return amount;
        } catch Error(string memory _err) {
            console.log("Repay Error");
            console.log(_err);
            return 0;
        }
    }
}
