// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// inheritances
import { ERC721Upgradeable } from "./ERC721Upgradeable.sol";
import { ERC721EnumerableUpgradeable } from "./ERC721EnumerableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ERC1967Proxy } from "./ERC1967Proxy.sol";

// libraries
import { SafeERC20 } from "./SafeERC20.sol";

// interfaces
import { IFactorLeverageDescriptor } from "./IFactorLeverageDescriptor.sol";
import { IStrategy } from "./IStrategy.sol";
import { IERC20 } from "./IERC20.sol";

interface ILeverageVault {
    function initialize(uint256, address, address, address, address, address) external;

    function assetBalance() external view returns (uint256);

    function debtBalance() external view returns (uint256);

    function asset() external view returns (address);

    function debtToken() external view returns (address);
}

contract FactorLeverageVault is Initializable, ERC721Upgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable {
    // =============================================================
    //                         Libraries
    // =============================================================

    using SafeERC20 for IERC20;

    // =============================================================
    //                          Events
    // =============================================================

    event PositionCreated(uint256 indexed id, address indexed vault);
    event AssetChanged(address token, address pool);
    event DebtChanged(address token, address pool);
    event UpgradeRegistered(address baseImpl, address upgradeImpl);
    event UpgradeRemoved(address baseImpl, address upgradeImpl);
    event DescriptorChanged(address descriptor);

    // =============================================================
    //                          Errors
    // =============================================================

    error INVALID_ASSET();
    error INVALID_DEBT();
    error ASSET_BALANCE_NOT_ZERO();

    // =============================================================
    //                      State Variables
    // =============================================================

    uint256 public constant FEE_SCALE = 1e18;

    uint256 public leverageFee;
    uint256 public claimRewardFee;

    address public feeRecipient;

    address public strategyImplementation;

    address public factorLeverageDescriptor;

    // The internal position ID tracker
    uint256 public currentPositionId;

    mapping(uint256 => address) public positions;

    // token => lending pool
    mapping(address => address) public assets;

    // token => lending pool
    mapping(address => address) public debts;

    mapping(address => mapping(address => bool)) internal isUpgrade;

    // =============================================================
    //                      Functions
    // =============================================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _strategyImplementation,
        address _factorLeverageDescriptor,
        string calldata _name,
        string calldata _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __Ownable_init();
        __ERC721Enumerable_init();
        strategyImplementation = _strategyImplementation;
        factorLeverageDescriptor = _factorLeverageDescriptor;
        claimRewardFee = 1e16;
        leverageFee = 1e16;
        feeRecipient = msg.sender;
    }

    function createPosition(address asset, address debt) external returns (uint256 id, address vault) {
        // validate if exist
        if (assets[asset] == address(0)) revert INVALID_ASSET();
        if (debts[debt] == address(0)) revert INVALID_DEBT();

        // mint
        _mint(msg.sender, currentPositionId);

        address assetPool = assets[asset];
        address debtPool = debts[debt];

        // deploy vault
        vault = address(new ERC1967Proxy(strategyImplementation, ''));
        ILeverageVault(vault).initialize(currentPositionId, address(this), asset, debt, assetPool, debtPool);

        positions[currentPositionId] = vault;

        emit PositionCreated(currentPositionId, vault);

        // increment id
        currentPositionId++;

        return (currentPositionId, vault);
    }

    function updateAsset(address asset, address pool) external onlyOwner {
        assets[asset] = pool;

        emit AssetChanged(asset, pool);
    }

    function updateDebt(address debt, address pool) external onlyOwner {
        debts[debt] = pool;

        emit DebtChanged(debt, pool);
    }

    function burnPosition(uint256 positionId) external {
        // balance must zero
        if (ILeverageVault(positions[positionId]).assetBalance() > 0) revert ASSET_BALANCE_NOT_ZERO();

        // remove position and burn
        positions[positionId] = address(0);
        _burn(positionId);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        address positionAddress = positions[id];

        IFactorLeverageDescriptor.TokenURIParams memory params = IFactorLeverageDescriptor.TokenURIParams({
            id: id,
            name: name(),
            description: symbol(),
            assetToken: ILeverageVault(positionAddress).asset(), // weth
            debtToken: ILeverageVault(positionAddress).debtToken(), // usdc
            assetAmount: ILeverageVault(positionAddress).assetBalance(),
            debtAmount: ILeverageVault(positionAddress).debtBalance()
        });

        return IFactorLeverageDescriptor(factorLeverageDescriptor).constructTokenURI(params);
    }

    function setDescriptor(address descriptor) external onlyOwner {
        factorLeverageDescriptor = descriptor;

        emit DescriptorChanged(descriptor);
    }

    // =============================================================
    //                      Upgrade
    // =============================================================

    function isRegisteredUpgrade(
        address baseImplementation,
        address upgradeImplementation
    ) external view returns (bool) {
        return isUpgrade[baseImplementation][upgradeImplementation];
    }

    function registerUpgrade(address baseImplementation, address upgradeImplementation) external onlyOwner {
        isUpgrade[baseImplementation][upgradeImplementation] = true;

        emit UpgradeRegistered(baseImplementation, upgradeImplementation);
    }

    function removeUpgrade(address baseImplementation, address upgradeImplementation) external onlyOwner {
        delete isUpgrade[baseImplementation][upgradeImplementation];

        emit UpgradeRemoved(baseImplementation, upgradeImplementation);
    }

    function updateImplementation(address _strategyImplementation) external onlyOwner {
        strategyImplementation = _strategyImplementation;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        feeRecipient = recipient;
    }

    function setLeverageFee(uint256 newFee) external onlyOwner {
        require(newFee <= FEE_SCALE, 'Invalid fee');
        leverageFee = newFee;
    }

    function setClaimRewardFee(uint256 newFee) external onlyOwner {
        require(newFee <= FEE_SCALE, 'Invalid fee');
        claimRewardFee = newFee;
    }

    function version() external pure returns (string memory) {
        return '1.0';
    }

    // =============================================================
    //                         Enumerables
    // =============================================================

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

