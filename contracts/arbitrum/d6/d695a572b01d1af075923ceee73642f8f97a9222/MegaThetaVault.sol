// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import "./ERC20Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";

import "./SafeERC20.sol";
import "./IERC20.sol";

import "./IMegaThetaVault.sol";
import "./IMegaThetaVaultManagement.sol";
import "./IComputedCVIOracle.sol";

contract MegaThetaVault is Initializable, IMegaThetaVault, IMegaThetaVaultManagement, OwnableUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    uint256 public constant MAX_PERCENTAGE = 10000;

    address public fulfiller;
    address public depositor;

    IThetaVault public override thetaVault;
    IThetaVault public ucviThetaVault;
    IERC20 internal token;

    uint256 public initialTokenToThetaTokenRate;

    uint256 public minRebalanceDiff;
    uint256 public depositCap;

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _initialTokenToThetaTokenRate, IThetaVault _thetaVault, IThetaVault _ucviThetaVault, 
            IERC20 _token, string memory _lpTokenName, string memory _lpTokenSymbolName) public initializer {
        require(address(_thetaVault) != address(0));
        require(address(_ucviThetaVault) != address(0));
        require(address(_token) != address(0));
        require(_initialTokenToThetaTokenRate > 0);

        initialTokenToThetaTokenRate = _initialTokenToThetaTokenRate;

        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        OwnableUpgradeable.__Ownable_init();
        ERC20Upgradeable.__ERC20_init(_lpTokenName, _lpTokenSymbolName);

        thetaVault = _thetaVault;
        ucviThetaVault = _ucviThetaVault;
        token = _token;
        minRebalanceDiff = 100000000; // 100 USD
        depositCap = type(uint256).max;

        token.safeApprove(address(thetaVault), type(uint256).max);
        token.safeApprove(address(ucviThetaVault), type(uint256).max);
        IERC20(address(thetaVault)).safeApprove(address(thetaVault), type(uint256).max);
        IERC20(address(ucviThetaVault)).safeApprove(address(ucviThetaVault), type(uint256).max);
    }

    function depositForOwner(address _owner, uint168 _tokenAmount, uint32 _realTimeCVIValue) external override returns (uint256 thetaTokensMinted) {
        require(msg.sender == fulfiller);

        (uint32 cviValue,,) = thetaVault.volToken().platform().cviOracle().getCVILatestRoundData();
        uint32 balanceCVIValue = cviValue;
        if (_realTimeCVIValue < balanceCVIValue) {
            balanceCVIValue = _realTimeCVIValue;
        }

        // Using minimum cvi value, so balance will be highest (as it makes platform balance larger), not allowing users to frontrun
        return _deposit(_owner, _tokenAmount, balanceCVIValue);
    }

    function deposit(uint168 _tokenAmount, uint32 _balanceCVIValue) external override returns (uint256 thetaTokensMinted) {
        require(msg.sender == depositor);
        return _deposit(msg.sender, _tokenAmount, _balanceCVIValue);
    }

    function withdrawForOwner(address _owner, uint168 _thetaTokenAmount, uint32 _realTimeCVIValue) external override returns (uint256 tokenWithdrawnAmount) {
        require(msg.sender == fulfiller);

        (uint32 cviValue,,) = thetaVault.volToken().platform().cviOracle().getCVILatestRoundData();
        uint32 burnCVIValue = cviValue;
        uint32 withdrawCVIValue = cviValue;

        if (_realTimeCVIValue < burnCVIValue) {
            burnCVIValue = _realTimeCVIValue;
        }

        if (_realTimeCVIValue > withdrawCVIValue) {
            withdrawCVIValue = _realTimeCVIValue;
        }

        // Using minimum cvi to burn tokens (so they yield less tokens in total worth), 
        // and maximum cvi for platform balance when withdrawing (as it makes platform balance smaller),
        // to have less total balance and not allow frontrun
        return _withdraw(_owner, _thetaTokenAmount, burnCVIValue, withdrawCVIValue);
    }

    function withdraw(uint168 _thetaTokenAmount, uint32 _burnCVIValue, uint32 _withdrawCVIValue) external override returns (uint256 tokenWithdrawnAmount) {
        require(msg.sender == depositor);
        return _withdraw(msg.sender, _thetaTokenAmount, _burnCVIValue, _withdrawCVIValue);
    }

    function setFulfiller(address _newFulfiller) external override onlyOwner {
        fulfiller = _newFulfiller;

        emit FulfillerSet(_newFulfiller);
    }

    function setDepositor(address _newDepositor) external override onlyOwner {
        depositor = _newDepositor;

        emit DepositorSet(_newDepositor);
    }

    function setDepositCap(uint256 _newDepositCap) external override onlyOwner {
        depositCap = _newDepositCap;

        emit DepositCapSet(_newDepositCap);
    }

    function setMinRebalanceDiff(uint256 _newMinRebalanceDiff) external override onlyOwner {
        minRebalanceDiff = _newMinRebalanceDiff;

        emit MinRebalanceDiffSet(_newMinRebalanceDiff);
    }

    function totalBalance(uint32 _balanceCVIValue) public view returns (uint256 balance, uint256 cviBalance, uint256 ucviBalance) {
        (cviBalance,,,,,) = thetaVault.totalBalance(_balanceCVIValue);
        uint32 balanceUCVIValue = IComputedCVIOracle(address(ucviThetaVault.platform().cviOracle())).getComputedCVIValue(_balanceCVIValue);
        (ucviBalance,,,,,) = ucviThetaVault.totalBalance(balanceUCVIValue);
        balance = cviBalance + ucviBalance;
    }

    function calculateOIBalance() external view override returns (uint256 oiBalance) {
        // Note: it's an estimation that because of using ucvi, the OI balance is worth about 3 times more than regular cvi OI
        // i.e. it needs three times as much hedge to cover for potential tripled gain
        oiBalance = thetaVault.calculateOIBalance() + ucviThetaVault.calculateOIBalance() * 3;
    }

    function calculateMaxOIBalance() external view override returns (uint256 maxOIBalance) {
        maxOIBalance = thetaVault.calculateMaxOIBalance() + ucviThetaVault.calculateMaxOIBalance() * 3;
    }

    function rebalance(uint16 _cviThetaVaultPercentage) external override onlyOwner {
        (uint32 cviValue,,) = thetaVault.volToken().platform().cviOracle().getCVILatestRoundData();
        (uint256 balance, uint256 cviBalance, uint256 ucviBalance) = totalBalance(cviValue);

        uint256 destinationCVIBalance = balance * _cviThetaVaultPercentage / MAX_PERCENTAGE;

        if (destinationCVIBalance > cviBalance && destinationCVIBalance - cviBalance >= minRebalanceDiff) {
            transferBetweenVaults(destinationCVIBalance - cviBalance, ucviThetaVault, thetaVault, cviBalance, cviValue);
        } else if (cviBalance > destinationCVIBalance && cviBalance - destinationCVIBalance >= minRebalanceDiff) {
            transferBetweenVaults(cviBalance - destinationCVIBalance, thetaVault, ucviThetaVault, ucviBalance, cviValue);
        }
    }

    function toUint168(uint256 x) private pure returns (uint168 y) {
        require((y = uint168(x)) == x);
    }

    function transferBetweenVaults(uint256 amount, IThetaVault fromThetaVault, IThetaVault toThetaVault, uint256 fromBalance, uint32 cviValue) private {
        uint168 thetaWithdrawTokens = toUint168(IERC20(address(fromThetaVault)).balanceOf(address(this)) * amount / fromBalance);
        uint168 withdrawnAmount = toUint168(fromThetaVault.withdraw(thetaWithdrawTokens, cviValue, cviValue));

        toThetaVault.deposit(withdrawnAmount, cviValue);
    }

    function _deposit(address _owner, uint168 _tokenAmount, uint32 _balanceCVIValue) private returns (uint256 megaThetaTokensMinted) {
        require(_tokenAmount > 0);

        (uint256 balance,,) = totalBalance(_balanceCVIValue);

        require(balance + _tokenAmount <= depositCap, "Cap exceeded");

        // Mint theta lp tokens
        if (totalSupply() > 0 && balance > 0) {
            megaThetaTokensMinted = (_tokenAmount * totalSupply()) / balance;
        } else {
            megaThetaTokensMinted = _tokenAmount * initialTokenToThetaTokenRate;
        }

        require(megaThetaTokensMinted > 0); // "Too few tokens"
        _mint(_owner, megaThetaTokensMinted);

        token.safeTransferFrom(_owner, address(this), _tokenAmount);

        (uint32 cviValue,,) = thetaVault.volToken().platform().cviOracle().getCVILatestRoundData();
        (uint32 ucviValue,,) = ucviThetaVault.volToken().platform().cviOracle().getCVILatestRoundData();

        uint256 thetaTokensMinted = thetaVault.deposit(_tokenAmount / 2, cviValue);
        uint256 ucviThetaTokensMinted = ucviThetaVault.deposit(_tokenAmount - _tokenAmount / 2, ucviValue);

        emit Deposit(_owner, _tokenAmount, thetaTokensMinted, ucviThetaTokensMinted, megaThetaTokensMinted);
    }

    function _withdraw(address _owner, uint168 _megaThetaTokenAmount, uint32 _burnCVIValue, uint32 _withdrawCVIValue) private returns (uint256 tokenWithdrawnAmount) {
        require(_megaThetaTokenAmount > 0);

        require(balanceOf(_owner) >= _megaThetaTokenAmount, "Not enough tokens");
        IERC20(address(this)).safeTransferFrom(_owner, address(this), _megaThetaTokenAmount);

        uint168 thetaTokensToRemove = toUint168((_megaThetaTokenAmount * IERC20(address(thetaVault)).balanceOf(address(this))) / totalSupply());
        uint168 ucviThetaTokensToRemove = toUint168((_megaThetaTokenAmount * IERC20(address(ucviThetaVault)).balanceOf(address(this))) / totalSupply());

        tokenWithdrawnAmount = thetaVault.withdraw(thetaTokensToRemove, _burnCVIValue, _withdrawCVIValue);
        tokenWithdrawnAmount += ucviThetaVault.withdraw(ucviThetaTokensToRemove,
            IComputedCVIOracle(address(ucviThetaVault.platform().cviOracle())).getComputedCVIValue(_burnCVIValue), 
            IComputedCVIOracle(address(ucviThetaVault.platform().cviOracle())).getComputedCVIValue(_withdrawCVIValue));

        _burn(address(this), _megaThetaTokenAmount);
        token.safeTransfer(_owner, tokenWithdrawnAmount);

        emit Withdraw(_owner, tokenWithdrawnAmount, thetaTokensToRemove, ucviThetaTokensToRemove, _megaThetaTokenAmount);
    }
}

