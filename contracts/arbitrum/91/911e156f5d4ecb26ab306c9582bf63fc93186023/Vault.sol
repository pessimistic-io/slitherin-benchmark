pragma solidity ^0.8.9;

import "./ERC4626Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./MathUpgradeable.sol";

import "./IVaultStrategy.sol";
import "./ITokenToUsdcOracle.sol";


contract Vault is ERC4626Upgradeable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using MathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct RequestedWithdraw {
        address from;
        uint256 assetsAmount;
        uint requestedAt;
    }

    /// @notice Responsible for all vault related permissions
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");
    /// @notice Role for vault assets delegation
    bytes32 internal constant VAULT_STRATEGIST_ROLE = keccak256("VAULT_STRATEGIST_ROLE");

    uint internal constant BP = 10_000;
    uint internal constant DELEGATE_AMOUNT_IN_BP = 9_000;

    struct WithdrawalQueueItem {
        uint256 id;
        address receiver;
        address owner;
        uint256 sharesAmount;
        uint256 assetsAmount;
        bool isOpen;
    }

    address strategist;
    EnumerableSetUpgradeable.AddressSet private strategies;
    EnumerableSetUpgradeable.AddressSet private tokens;
    mapping(address => address) private tokensOracles;

    uint256 private minValueToDelegate;
    uint256 private withdrawQueueItemId;
    mapping(uint => WithdrawalQueueItem) public withdrawQueue;


    event RequestWithdraw(uint id, address receiver, uint assets, uint shares);
    event WithdrawApproved(address strategist, uint id, address receiver, address owner, uint assets, uint shares);
    event Withdrawn(address receiver, uint assets, uint shares);
    event Deposited(address receiver, uint assets, uint shares);
    event Delegated(address indexed strategist, uint assets);

    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        address _strategist
    ) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_STRATEGIST_ROLE, _strategist);
        __ERC4626_init(IERC20MetadataUpgradeable(_asset));
        __ERC20_init(_name, _symbol);
        __ReentrancyGuard_init();
        __AccessControl_init();

        minValueToDelegate = 3_000 * 1e6;
        strategist = _strategist;
        withdrawQueueItemId = 0;
    }

    function addTokenOracle(address _token, address _tokenOracle) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.add(tokens, _token);
        tokensOracles[_token] = _tokenOracle;
    }

    function setStrategist(address _strategist) public onlyRole(DEFAULT_ADMIN_ROLE) {
        strategist = _strategist;
    }

    function removeTokenOracle(address _token) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.remove(tokens, _token);
        delete tokensOracles[_token];
    }

    function getTokenOracles() public view returns(address[] memory) {
        return EnumerableSetUpgradeable.values(strategies);
    }

    function addStrategy(address _strategy) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.add(strategies, _strategy);
    }

    function removeStrategy(address _strategy) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.remove(strategies, _strategy);
    }

    function getStrategies() public view returns(address[] memory) {
        return EnumerableSetUpgradeable.values(strategies);
    }

    function delegate(address _to, uint256 _assets) public  {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), _to, _assets);

        emit Delegated(_to, _assets);
    }

    function mint(uint256 _shares, address _receiver) public override returns (uint256) {
        require(_shares <= maxMint(_receiver), "maxMint");

        uint256 assets = _convertToAssets(_shares, MathUpgradeable.Rounding.Ceil);

        _deposit(msg.sender, _receiver, assets, _shares);

        _delegateToStrategistIfNeeded();

        emit Deposited(_receiver, assets, _shares);

        return assets;
    }

    function deposit(uint256 _assets, address _receiver) public override returns (uint256) {
        require(_assets <= maxDeposit(_receiver), "maxMint");

        uint256 shares = convertToShares(_assets);

        _deposit(msg.sender, _receiver, _assets, shares);

        _delegateToStrategistIfNeeded();

        emit Deposited(_receiver, _assets, shares);

        return shares;
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        require(_assets <= maxWithdraw(_owner), "maxWithdraw");

        uint256 balance = _vaultBalance();
        uint shares = _convertToShares(_assets, MathUpgradeable.Rounding.Ceil);

        if (balance >= _assets) {
            _withdraw(msg.sender, _receiver, _owner, _assets, shares);
            emit Withdrawn(_receiver, _assets, shares);
        } else {
            uint256 queueItemId = _createQueueItem(_receiver, _owner, shares, _assets);
            emit RequestWithdraw(queueItemId, _receiver, _assets, shares);
        }

        return shares;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        require(_shares <= maxRedeem(_owner), "maxRedeem");

        uint256 balance = _vaultBalance();
        uint256 assets = convertToAssets(_shares);

        if (balance >= assets) {
            _withdraw(msg.sender, _receiver, _owner, assets, _shares);
            emit Withdrawn(_receiver, assets, _shares);
        } else {
            uint256 queueItemId = _createQueueItem(_receiver, _owner, _shares, assets);
            emit RequestWithdraw(queueItemId, _receiver, assets, _shares);
        }

        return assets;
    }

    function approveWithdraw(uint256 _withdrawQueueItemId) public returns (uint256) {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        WithdrawalQueueItem storage withdrawQueueItem = withdrawQueue[_withdrawQueueItemId];

        require(withdrawQueueItem.isOpen, "Queue request closed or not defined");

        uint256 balance = _vaultBalance();

        require(balance >= withdrawQueueItem.assetsAmount, "Not enough assets to approve withdraw");

        _burn(withdrawQueueItem.owner, withdrawQueueItem.sharesAmount);

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), withdrawQueueItem.receiver, withdrawQueueItem.assetsAmount);

        withdrawQueue[_withdrawQueueItemId].isOpen = false;

        emit Withdraw(msg.sender, withdrawQueueItem.receiver, withdrawQueueItem.owner, withdrawQueueItem.assetsAmount, withdrawQueueItem.sharesAmount);
        emit WithdrawApproved(msg.sender, _withdrawQueueItemId, withdrawQueueItem.receiver, withdrawQueueItem.owner, withdrawQueueItem.assetsAmount, withdrawQueueItem.sharesAmount);

        return withdrawQueueItem.assetsAmount;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 virtualTotalAssets = _vaultBalance();

        for (uint i = 0; i < EnumerableSetUpgradeable.length(strategies); i++) {
            IVaultStrategy strategy = IVaultStrategy(EnumerableSetUpgradeable.at(strategies, i));
            virtualTotalAssets += strategy.getBalance(strategist);
        }

        for (uint i = 0; i < EnumerableSetUpgradeable.length(tokens); i++) {
            address tokenAddress = EnumerableSetUpgradeable.at(tokens, i);
            ITokenToUsdcOracle tokenOracle = ITokenToUsdcOracle(tokensOracles[tokenAddress]);
            uint256 strategistTokenBalance = IERC20Upgradeable(tokenAddress).balanceOf(strategist);
            virtualTotalAssets += tokenOracle.usdcAmount(strategistTokenBalance);
        }

        virtualTotalAssets += _getStrategistAssetsBalance();

        return virtualTotalAssets;
    }

    // save shares and assets amount to bind price
    function _createQueueItem(address _receiver, address _owner, uint256 _shares, uint256 _assets) internal returns (uint256) {
        uint queueItemId = _getWithdrawQueueItemId();

        WithdrawalQueueItem storage queueItem = withdrawQueue[queueItemId];

        queueItem.id = queueItemId;
        queueItem.receiver = _receiver;
        queueItem.owner = _owner;
        queueItem.sharesAmount = _shares;
        queueItem.assetsAmount = _assets;
        queueItem.isOpen = true;

        return queueItemId;
    }

    function _calculatePercent(uint256 amount, uint256 bps) internal pure returns (uint256) {
        require((amount * bps) >= BP);
        return amount * bps / BP;
    }

    function _delegateToStrategistIfNeeded() internal {
        uint256 balance = _vaultBalance();

        uint256 activeAssets = _calculatePercent(balance, DELEGATE_AMOUNT_IN_BP);

        if (activeAssets >= minValueToDelegate) {
            SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), strategist, activeAssets);
            emit Delegated(strategist, activeAssets);
        }
    }

    function _vaultBalance() internal view returns(uint256) {
        return IERC20Upgradeable(asset()).balanceOf(address(this));
    }

    function _getStrategistAssetsBalance() internal view returns(uint256) {
        return IERC20Upgradeable(asset()).balanceOf(strategist);
    }

    function _getWithdrawQueueItemId() internal returns(uint256) {
        return withdrawQueueItemId++;
    }
}

