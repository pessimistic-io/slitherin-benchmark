//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Pausable} from "./Pausable.sol";
import {Math} from "./Math.sol";
import {ERC4626} from "./ERC4626.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC20} from "./ERC20.sol";
import {IERC20} from "./interfaces_IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Address} from "./Address.sol";

import {IBartender} from "./IBartender.sol";
import {Constant} from "./Constant.sol";
import {IWater} from "./IWater.sol";

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Responsible for our customers not getting intoxicated
 * @notice The underlying asset is USDC which will provide the shares in WATER. For more
 * information about Tokenized Vaults, please refer to https://eips.ethereum.org/EIPS/eip-4626
 */
contract Water is IWater, ERC4626, Ownable, Pausable, Constant {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /** @dev Water related variables */
    IERC20 public immutable usdcToken;
    uint256 private _assetCap;
    address private _feeRecipient;
    uint256 private _totalDebt;
    uint96 private _feeBPS = 0; // 0.5%

    /** @dev Bartender related variables */
    IBartender public bartender;
    address public liquor;

    constructor(address _usdcToken) ERC4626(IERC20(_usdcToken)) ERC20("Water", "S-WATER") {
        usdcToken = IERC20(_usdcToken);
    }

    modifier onlyBartenderOrLiquor() {
        if (_msgSender() != address(bartender) && _msgSender() != address(liquor))
            revert ThrowPermissionDenied({admin: address(bartender), sender: _msgSender()});
        _;
    }

    /* ##################################################################
                                OWNER FUNCTIONS
    ################################################################## */
    /// @dev See {IWater-settingManagerAddr}
    function settingManagerAddr(bytes32 params, address value) external onlyOwner {
        if (value == address(0)) revert ThrowZeroAddress();
        if (params == "bartender") {
            if (!Address.isContract(value)) revert ThrowInvalidContract(value);
            else bartender = IBartender(value);
        } else if (params == "fee") _feeRecipient = value;
        else if (params == "liquor") liquor = value;
        else revert ThrowInvalidParamsAddr(params, value);
        emit SettingManagerAddr(params, value);
    }

    /// @dev See {IWater-settingManagerValue}
    function settingManagerValue(bytes32 params, uint256 value) external onlyOwner {
        if (params == "feeBPS") _feeBPS = uint96(value);
        else if (params == "cap") _assetCap = value;
        else revert ThrowInvalidParamsValue(params, value);
        emit SettingManagerValue(params, value);
    }

    /// @dev See {IWater-leverageVault}
    function leverageVault(uint256 _amount) external onlyBartenderOrLiquor {
        uint256 usdcBalance = usdcToken.balanceOf(address(this));
        if (_amount > usdcBalance) revert ThrowUnavailableSupply({totalSupply: usdcBalance, withdrawAmount: _amount});

        _totalDebt += _amount;
        usdcToken.safeTransfer(address(bartender), _amount);

        emit LeverageBartender(_amount, block.timestamp);
    }

    /// @dev See {IWater-repayDebt}
    function repayDebt(uint256 _amount) external onlyBartenderOrLiquor {
        _totalDebt -= _amount;

        if (_msgSender() == address(bartender)) {
            usdcToken.safeTransferFrom(address(bartender), address(this), _amount);
        } else {
            usdcToken.safeTransferFrom(liquor, address(this), _amount);
        }

        emit LeverageBartenderDebt(_amount, _totalDebt, block.timestamp);
    }

    /* ##################################################################
                                USER FUNCTIONS
    ################################################################## */
    /// @notice withdraws USDC if there is enough supply with 0.5% withdrawal fee
    /// @param _assets amount of USDC to be given to the user (6 decimals)
    /// @param _receiver who will receive the USDC
    /// @param _owner who owns the assets
    /// @return shares WATER shares burned for _receiver
    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override whenNotPaused returns (uint256 shares) {
        if (_feeRecipient == address(0)) revert ThrowZeroAddress();

        shares = previewWithdraw(_assets);
        _transferRecipientFee(bytes32("withdraw"), _assets);
        _withdraw(_msgSender(), _receiver, _owner, _assets, shares);

        return shares;
    }

    /// @notice deposits USDC to the vault, and mint WATER to the user
    /// @param _assets amount of USDC to be deposit to vault (6 decimals)
    /// @param _receiver who will receive the WATER LP
    /// @return shares total WATER shares minted for _receiver
    function deposit(uint256 _assets, address _receiver) public override whenNotPaused returns (uint256 shares) {
        if (_feeRecipient == address(0)) revert ThrowZeroAddress();
        if (_assets >= maxDeposit(_receiver)) revert ThrowAssetCap({amount: _assets, expected: maxDeposit(_receiver)});

        uint256 fees = _transferRecipientFee(bytes32("deposit"), _assets);
        uint256 assetsAfterFee = _assets - fees;
        shares = previewDeposit(_assets);
        _deposit(_msgSender(), _receiver, assetsAfterFee, shares);

        emit WaterDeposit(_receiver, _assets);
        return shares;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override whenNotPaused returns (uint256 shares) {
        if (_feeRecipient == address(0)) revert ThrowZeroAddress();

        shares = previewRedeem(_shares);
        _transferRecipientFee(bytes32("withdraw"), _shares);
        _withdraw(_msgSender(), _receiver, _owner, _shares, shares);

        return shares;
    }

    /// @notice disable ERC4626 `mint`
    function mint(uint256, address) public virtual override returns (uint256) {
        revert ThrowInvalidFunction();
    }

    /* ##################################################################
                                VIEW FUNCTIONS
    ################################################################## */
    /// @notice calculate the current balance in Water and totalDebt Sake have leveraged
    /// @return _totalAssets total of assets in USDC (6 decimals)
    function totalAssets() public view override returns (uint256 _totalAssets) {
        return usdcToken.balanceOf(address(this)) + _totalDebt;
    }

    /// @return feeBPS_ gets the protocol fee
    function getFeeBPS() public view returns (uint256 feeBPS_) {
        return _feeBPS;
    }

    /// @return feeRecipient_ gets the fee recipient address
    function getFeeRecipient() public view returns (address feeRecipient_) {
        return _feeRecipient;
    }

    /// @return assetCap_ gets the underlying asset cap
    function getAssetCap() public view returns (uint256 assetCap_) {
        return _assetCap;
    }

    function previewWithdraw(uint256 _assets) public view override returns (uint256) {
        uint256 fees = _assets.mulDiv(_feeBPS, MAX_BPS);
        _assets = _assets - fees;
        return _convertToShares(_assets, Math.Rounding.Up);
    }

    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        uint256 fees = _assets.mulDiv(_feeBPS, MAX_BPS);
        _assets = _assets - fees;
        return _convertToShares(_assets, Math.Rounding.Down);
    }

    function previewRedeem(uint256 _shares) public view override returns (uint256) {
        uint256 fees = _shares.mulDiv(_feeBPS, MAX_BPS);
        _shares = _shares - fees;
        return _convertToAssets(_shares, Math.Rounding.Down);
    }

    function getTotalDebt() public view returns (uint256) {
        return _totalDebt;
    }

    function updateTotalDebt(uint256 profit) public onlyBartenderOrLiquor returns (uint256) {
        _totalDebt += profit;
        return _totalDebt;
    }

    function getUtilizationRatio() public view returns (uint256) {
        return _totalDebt.mulDiv(RATE_PRECISION, totalAssets());
    }

    function getWaterPrice() public view returns (uint256) {
        return _calculateWaterPrice();
    }

    /* ##################################################################
                                INTERNAL FUNCTIONS
    ################################################################## */
    /// @notice internal helper function to calculate the fee
    /// @param _params takes the bytes32 params name
    /// @param _assets total fees to be transferred to fee recipient
    function _transferRecipientFee(bytes32 _params, uint256 _assets) internal returns (uint256) {
        uint256 fees = _assets.mulDiv(_feeBPS, MAX_BPS);
        if (_params == "deposit") {
            usdcToken.safeTransferFrom(_msgSender(), _feeRecipient, fees);
        }

        if (_params == "withdraw") {
            uint256 shares = _convertToShares(fees, Math.Rounding.Up);
            usdcToken.safeTransfer(_feeRecipient, shares);
        }
        return fees;
    }

    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        return assets.mulDiv(_calculateWaterPrice(), 10 ** 6, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        return shares.mulDiv(10 ** 6, _calculateWaterPrice(), rounding);
    }

    /// @notice when the total supply of underlying asset is 0 than is $1.
    /// @return waterPrice 6 decimals
    function _calculateWaterPrice() internal view returns (uint256 waterPrice) {
        if (totalAssets() == 0) {
            return WATER_DEFAULT_PRICE;
        } else {
            return totalAssets().mulDiv(10 ** 6, totalSupply());
        }
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    ) internal virtual override {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }
        _burn(_owner, _shares);
        usdcToken.safeTransfer(_caller, _shares);

        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal virtual override {
        usdcToken.safeTransferFrom(_caller, address(this), _assets);
        _mint(_receiver, _shares);

        emit Deposit(_caller, _receiver, _assets, _shares);
    }
}

