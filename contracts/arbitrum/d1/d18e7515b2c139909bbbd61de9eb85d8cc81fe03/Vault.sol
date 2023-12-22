// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

import "./ProtocolFee.sol";

abstract contract Vault is
    ERC20,
    AccessControl,
    Pausable,
    ReentrancyGuard,
    ProtocolFee
{
    using SafeERC20 for IERC20;
    using FixedPointMathLib for uint256;

    IERC20 public depositableToken;
    uint256 public minimumDeposit;
    uint256 public maximumDeposit;

    // =============================================================
    //                        Modifiers
    // =============================================================
    modifier whenNoActiveDeposits() {
        require(totalSupply() == 0, "Active deposits exist");
        _;
    }

    // =============================================================
    //                        Initialize
    // =============================================================
    constructor(address _depostiableToken) ERC20("TokenizedVault", "TKNV") {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        depositableToken = IERC20(_depostiableToken);

        // Set the default values for minimum and maximum deposits in the constructor
        uint8 decimals = ERC20(_depostiableToken).decimals();
        setMinimumDeposit(10**decimals); // Default: 1 token
        setMaximumDeposit(type(uint256).max); // Default: uint256 max

        addFeeInfo(0, Fee(FeeType.Bps, 0, 0, msg.sender));  // Management Fee: 0% 
        addFeeInfo(1, Fee(FeeType.Bps, 3_000, 0, msg.sender));  // Performance Fee: 30% 
    }

    // =============================================================
    //                 Manager Functions
    // =============================================================
    function pauseVault() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpauseVault() public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setDepositableToken(address _depositableToken)
        external
        virtual
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNoActiveDeposits
    {
        depositableToken = IERC20(_depositableToken);
    }

    // =============================================================
    //                  Accounting Logic
    // =============================================================
    function totalValueLocked()
        public
        view
        virtual
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](1);
        amounts[0] = depositableToken.balanceOf(address(this));
    }

    function convertToShares(uint256[] memory assets)
        public
        view
        virtual
        returns (uint256)
    {
        require(address(depositableToken) != address(0), "depositableToken not set");

        uint256 totalShares = totalSupply();
        if (totalShares == 0) return assets[0];

        uint256[] memory tvl = totalValueLocked();
        require(tvl.length == 1, "TVL must return 1");

        return assets[0].mulDivDown(totalShares, tvl[0]);
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        returns (uint256[] memory assets)
    {
        require(shares != 0, "ZERO_SHARES");
        require(address(depositableToken) != address(0), "depositableToken not set");

        assets = new uint256[](1);

        uint256[] memory tvl = totalValueLocked();
        require(tvl.length == 1, "TVL must return 1");

        uint256 totalShares = totalSupply();
        assets[0] = totalShares <= shares ? tvl[0] : shares.mulDivDown(tvl[0], totalShares);
    }

    // =============================================================
    //               DEPOSIT/WITHDRAWAL LIMIT LOGIC
    // =============================================================
    function setMinimumDeposit(uint256 newMinimum)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        minimumDeposit = newMinimum;
    }

    function setMaximumDeposit(uint256 newMaximum)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        maximumDeposit = newMaximum;
    }

    function maxDeposit() public view virtual returns (uint256) {
        return maximumDeposit;
    }

    function minDeposit() public view virtual returns (uint256) {
        return minimumDeposit;
    }

    // =============================================================
    //                    INTERNAL HOOKS LOGIC
    // =============================================================
    function _processDepositAmount(uint256 depositAmount)
        internal
        virtual
        returns (uint256[] memory assets) 
    {
        assets = new uint256[](1);
        assets[0] = depositAmount;
    }

    function _processWithdrawAmount(uint256[] memory assets)
        internal
        virtual
        returns (uint256)
    {
        return assets[0];
    }

    /**
     *  This function returns who is authorized to set fee info for this contract.
     */
    function _canSetFeeInfo() 
        internal 
        view 
        virtual 
        override 
        returns (bool) 
    {
        return hasRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}

