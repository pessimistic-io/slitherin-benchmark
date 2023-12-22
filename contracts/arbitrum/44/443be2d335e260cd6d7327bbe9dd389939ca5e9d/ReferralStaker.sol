// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { IReferralStorage } from "./IReferralStorage.sol";

interface ICreditCallers {
    function openLendCredit(
        address _depositor,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable;

    function openLendCredit(
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient
    ) external payable;

    function creditUser() external view returns (address);
}

interface ICreditUser {
    function getUserCounts(address _recipient) external view returns (uint256);
}

interface IAbstractVault {
    function addLiquidity(uint256 _amountIn) external payable returns (uint256);

    function supplyRewardPool() external view returns (address);
}

interface IBaseReward {
    function stakeFor(address _recipient, uint256 _amountIn) external;

    function withdraw(uint256 _amountOut) external returns (uint256);
}

contract ReferralStaker is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant STAKED_GLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;

    address public referralStorage;

    struct CreditData {
        address creditCaller;
        address creditUser;
    }

    struct AbstractVault {
        address vault;
        address supplyRewardPool;
    }

    mapping(address => CreditData) private creditDatas;
    mapping(address => AbstractVault) private abstractVaults;

    event OpenLendCreditReferral(
        address indexed creditCaller,
        address indexed creditUser,
        address _recipient,
        uint256 _borrowedIndex,
        address _token,
        uint256 _amountIn,
        bytes32 _referralCode
    );
    event SetCreditData(address _collateralToken, address _creditCaller, address _creditUser);
    event SetAbstractVaults(address _underlyingToken, address _vault, address _supplyRewardPool);
    event AddLiquidityReferral(address _vault, address _underlyingToken, uint256 _amountIn, uint256 _amountOut, bytes32 _referralCode);

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /// @notice used to initialize the contract
    function initialize(address _referralStorage) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init();

        referralStorage = _referralStorage;
    }

    function setCreditData(address _collateralToken, address _creditCaller) external onlyOwner {
        address creditUser = ICreditCallers(_creditCaller).creditUser();

        creditDatas[_collateralToken] = CreditData({ creditCaller: _creditCaller, creditUser: creditUser });

        emit SetCreditData(_collateralToken, _creditCaller, creditUser);
    }

    function setAbstractVaults(address _underlyingToken, address _vault) external onlyOwner {
        address supplyRewardPool = IAbstractVault(_vault).supplyRewardPool();

        abstractVaults[_underlyingToken] = AbstractVault({ vault: _vault, supplyRewardPool: supplyRewardPool });

        emit SetAbstractVaults(_underlyingToken, _vault, supplyRewardPool);
    }

    function openLendCreditGlp(
        address _depositor,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient,
        bytes32 _referralCode
    ) external payable nonReentrant {
        CreditData storage creditData = creditDatas[STAKED_GLP];

        {
            uint256 before = IERC20Upgradeable(STAKED_GLP).balanceOf(address(this));
            IERC20Upgradeable(STAKED_GLP).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(STAKED_GLP).balanceOf(address(this)) - before;
        }

        _setReferralCode(_referralCode);
        _approve(STAKED_GLP, creditData.creditCaller, _amountIn);

        ICreditCallers(creditData.creditCaller).openLendCredit(_depositor, _amountIn, _borrowedTokens, _ratios, _recipient);
        uint256 borrowedIndex = ICreditUser(creditData.creditUser).getUserCounts(_recipient);

        emit OpenLendCreditReferral(creditData.creditCaller, creditData.creditUser, _recipient, borrowedIndex, STAKED_GLP, _amountIn, _referralCode);
    }

    function openLendCredit(
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios,
        address _recipient,
        bytes32 _referralCode
    ) external payable nonReentrant {
        CreditData storage creditData = creditDatas[_token];

        if (_token != ZERO) {
            uint256 before = IERC20Upgradeable(_token).balanceOf(address(this));
            IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_token).balanceOf(address(this)) - before;

            _approve(_token, creditData.creditCaller, _amountIn);
        }

        _setReferralCode(_referralCode);

        ICreditCallers(creditData.creditCaller).openLendCredit{ value: msg.value }(_depositor, _token, _amountIn, _borrowedTokens, _ratios, _recipient);
        uint256 borrowedIndex = ICreditUser(creditData.creditUser).getUserCounts(_recipient);

        emit OpenLendCreditReferral(creditData.creditCaller, creditData.creditUser, _recipient, borrowedIndex, _token, _amountIn, _referralCode);
    }

    function addLiquidity(address _underlyingToken, uint256 _amountIn, bytes32 _referralCode) external payable returns (uint256) {
        AbstractVault storage abstractVault = abstractVaults[_underlyingToken];

        if (_underlyingToken != ZERO) {
            uint256 before = IERC20Upgradeable(_underlyingToken).balanceOf(address(this));
            IERC20Upgradeable(_underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(_underlyingToken).balanceOf(address(this)) - before;

            _approve(_underlyingToken, abstractVault.vault, _amountIn);
        }

        uint256 amountOut = IAbstractVault(abstractVault.vault).addLiquidity{ value: msg.value }(_amountIn);

        _setReferralCode(_referralCode);
        _approve(abstractVault.vault, abstractVault.supplyRewardPool, amountOut);

        IBaseReward(abstractVault.supplyRewardPool).withdraw(amountOut);
        IBaseReward(abstractVault.supplyRewardPool).stakeFor(msg.sender, amountOut);

        emit AddLiquidityReferral(abstractVault.vault, _underlyingToken, _amountIn, amountOut, _referralCode);

        return amountOut;
    }

    function _setReferralCode(bytes32 _referralCode) internal {
        if (_referralCode != bytes32(0) && referralStorage != address(0)) {
            IReferralStorage(referralStorage).setReferralCode(msg.sender, _referralCode);
        }
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

