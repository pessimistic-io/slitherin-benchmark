pragma solidity ^0.8.9;

import "./ERC4626Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./EnumerableMapUpgradeable.sol";
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
        uint256 timestamp;
    }

    address strategist;
    EnumerableSetUpgradeable.AddressSet private strategies;
    EnumerableSetUpgradeable.AddressSet private tokens;
    mapping(address => address) private tokensOracles;

    uint256 private minValueToDelegate;
    uint256 private withdrawQueueItemId;
    mapping(uint => WithdrawalQueueItem) public withdrawQueue;

    uint internal feeInBp;
    EnumerableMapUpgradeable.AddressToUintMap private depositsInAssets;
    address internal ethToAssetOracle;

    event RequestWithdraw(uint id, address receiver, uint assets, uint shares);
    event WithdrawApproved(address strategist, uint id, address receiver, address owner, uint assets, uint shares);
    event Withdrawn(address receiver, uint assets, uint shares);
    event Deposited(address receiver, uint assets, uint shares);
    event Delegated(address indexed strategist, uint assets);
    event FeeCollected(address from, uint shares, uint assets);

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
        feeInBp = 2_000;
        ethToAssetOracle = 0x6F0a1016C99dd7b3FbF4a84b72d719bD680F96CE;
    }

    function setFeeInBp(uint _fee) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        feeInBp = _fee;
    }

    function addTokenOracle(address _token, address _tokenOracle) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.add(tokens, _token);
        tokensOracles[_token] = _tokenOracle;
    }

    function setEthToAssetOracle(address _oracle) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        ethToAssetOracle = _oracle;
    }

    function setStrategist(address _strategist) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(VAULT_STRATEGIST_ROLE, strategist);
        _grantRole(VAULT_STRATEGIST_ROLE, _strategist);
        strategist = _strategist;
    }

    function getStrategist() public view returns(address) {
        return strategist;
    }

    function removeTokenOracle(address _token) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        EnumerableSetUpgradeable.remove(tokens, _token);
        delete tokensOracles[_token];
    }

    function getTokenOracles() public view returns(address[] memory, address[] memory) {
        address[] memory tokensOraclesAddresses = new address[](EnumerableSetUpgradeable.length(tokens));

        for (uint i = 0; i < EnumerableSetUpgradeable.length(tokens); i++) {
            address tokenAddress = EnumerableSetUpgradeable.at(tokens, i);
            tokensOraclesAddresses[i] = tokensOracles[tokenAddress];
        }

        return (EnumerableSetUpgradeable.values(tokens), tokensOraclesAddresses);
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

        _addUserDeposit(_receiver, assets);


        emit Deposited(_receiver, assets, _shares);

        return assets;
    }

    function deposit(uint256 _assets, address _receiver) public override returns (uint256) {
        require(_assets <= maxDeposit(_receiver), "maxMint");

        uint256 shares = convertToShares(_assets);

        _deposit(msg.sender, _receiver, _assets, shares);

        _delegateToStrategistIfNeeded();

        _addUserDeposit(_receiver, _assets);

        emit Deposited(_receiver, _assets, shares);

        return shares;
    }

    function withdraw(
        uint256 _assets,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        require(_assets <= maxWithdraw(_owner), "maxWithdraw");

        uint shares = _convertToShares(_assets, MathUpgradeable.Rounding.Ceil);

        uint256 queueItemId = _createQueueItem(_receiver, _owner, shares, _assets);
        emit RequestWithdraw(queueItemId, _receiver, _assets, shares);

        return shares;
    }

    function redeem(
        uint256 _shares,
        address _receiver,
        address _owner
    ) public override returns (uint256) {
        require(_shares <= maxRedeem(_owner), "maxRedeem");

        uint256 assets = convertToAssets(_shares);

        uint256 queueItemId = _createQueueItem(_receiver, _owner, _shares, assets);
        emit RequestWithdraw(queueItemId, _receiver, assets, _shares);

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

        uint assetsAmount = convertToAssets(withdrawQueueItem.sharesAmount);

        require(balance >= assetsAmount, "Not enough assets to approve withdraw");

        uint assetsToWithdraw = _collectFee(withdrawQueueItem.receiver, assetsAmount);

        _burn(withdrawQueueItem.owner, withdrawQueueItem.sharesAmount);

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), withdrawQueueItem.receiver, assetsToWithdraw);

        withdrawQueue[_withdrawQueueItemId].isOpen = false;

        emit Withdraw(msg.sender, withdrawQueueItem.receiver, withdrawQueueItem.owner, assetsAmount, withdrawQueueItem.sharesAmount);
        emit WithdrawApproved(msg.sender, _withdrawQueueItemId, withdrawQueueItem.receiver, withdrawQueueItem.owner, assetsAmount, withdrawQueueItem.sharesAmount);

        return assetsAmount;
    }

    function closeWithdraw(uint256 _withdrawQueueItemId) public {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(VAULT_STRATEGIST_ROLE, msg.sender),
            "Permission denied"
        );

        if (withdrawQueue[_withdrawQueueItemId].isOpen) {
            withdrawQueue[_withdrawQueueItemId].isOpen = false;
        }
    }

    function getWithdrawQueue() public view returns(WithdrawalQueueItem[] memory withdrawItems) {
        withdrawItems = new WithdrawalQueueItem[](withdrawQueueItemId);

        for (uint i = 0; i < withdrawQueueItemId; i++) {
            withdrawItems[i] = (withdrawQueue[i]);
        }

        return withdrawItems;
    }

    function getDepositsInAssets(address _from) public view returns(uint) {
        (bool success, uint assets) = EnumerableMapUpgradeable.tryGet(depositsInAssets, _from);

        return assets;
    }

    function _collectFee(address _from, uint256 _assets) internal returns(uint256 assetsToWithdraw) {
        uint256 sharesBalance = balanceOf(address(_from));
        uint256 assetsBalance = convertToAssets(sharesBalance);
        uint256 depositInAssets = EnumerableMapUpgradeable.get(depositsInAssets, _from);

        uint256 earnings = 0;

        if (assetsBalance > depositInAssets) {
            earnings = assetsBalance - depositInAssets;
        }

        uint256 collectFeeFrom = _assets;

        if (_assets > earnings) {
            uint assetsToSubFromDeposit = _assets - earnings;
            collectFeeFrom = earnings;
            _subUserDeposit(_from, assetsToSubFromDeposit);
        }

        if (collectFeeFrom < BP) {
            assetsToWithdraw = _assets;
            return assetsToWithdraw;
        }

        uint feeInAssets = _calculatePercent(collectFeeFrom, feeInBp);
        assetsToWithdraw = _assets - feeInAssets;

        uint feeInShares = convertToShares(feeInAssets);
        _mint(strategist, feeInShares);

        emit FeeCollected(_from, feeInShares, feeInAssets);
        return assetsToWithdraw;
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
        virtualTotalAssets += _getStrategistEthInAssetsBalance();

        return virtualTotalAssets;
    }

    function _getStrategistEthInAssetsBalance() internal view returns(uint256) {
        ITokenToUsdcOracle oracle = ITokenToUsdcOracle(ethToAssetOracle);
        return oracle.usdcAmount(address(strategist).balance);
    }

    function _addUserDeposit(address _receiver, uint256 _assets) internal {
        if (EnumerableMapUpgradeable.contains(depositsInAssets, _receiver)) {
            uint256 userDepositsInAssets = EnumerableMapUpgradeable.get(depositsInAssets, _receiver);
            EnumerableMapUpgradeable.set(depositsInAssets, _receiver, userDepositsInAssets + _assets);
        } else {
            EnumerableMapUpgradeable.set(depositsInAssets, _receiver, _assets);
        }
    }

    function _subUserDeposit(address _receiver, uint256 _assets) internal {
        uint256 userDepositsInAssets = EnumerableMapUpgradeable.get(depositsInAssets, _receiver);
        EnumerableMapUpgradeable.set(depositsInAssets, _receiver, userDepositsInAssets - _assets);
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
        queueItem.timestamp = block.timestamp;

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

    function transferFrom(address from, address to, uint256 value) override(ERC20Upgradeable, IERC20Upgradeable) public virtual returns(bool) {
        revert("Token non transferable");
        return false;
    }

    function transfer(address to, uint256 value) override(ERC20Upgradeable, IERC20Upgradeable) public virtual returns (bool) {
        revert("Token non transferable");
        return false;
    }
}

