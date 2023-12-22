// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./IStrategyRegistry.sol";

// Proxy Support
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./UUPSUpgradeable.sol";

// Access Control
import "./AccessControlUpgradeable.sol";

// 721 Support
import "./ERC721Upgradeable.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./ERC721PausableUpgradeable.sol";

/// @title A registry for strategies
/// @author Steer Protocol
/// @dev All strategies are registered through this contract.
/// @dev This is where strategy bundles are stored as well as the offline data needed to decode parameters stored on a vault.
contract StrategyRegistry is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721EnumerableUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    // Library setup
    using CountersUpgradeable for CountersUpgradeable.Counter;

    string internal _baseTokenURI;

    // Mapping for pulling strategy details from the registry by the hash of the ipfs cid
    //    CID => RegisteredStrategy
    mapping(string => IStrategyRegistry.RegisteredStrategy) public strategies;

    // Mapping for pulling strategy ipfs cid by the ERC721 tokenId associated
    //   ERC721 tokenId => CID
    mapping(uint256 => string) public tokenIdToExecBundle;

    // Counter to keep track of totalSupply
    CountersUpgradeable.Counter public _tokenIdTracker;

    // Set up roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // Gas configuration limits
    uint256 public maxMaxGasPerAction; // Max allowable maxGasPerAction. Attempting to set a maxGasPerAction higher than this will revert.

    // Misc constants
    bytes32 public constant hashedEmptyString = keccak256("");

    event StrategyCreated(
        address indexed owner,
        uint256 indexed tokenId,
        string name //IPFS identifier of execution bundle
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    function initialize(string memory registry) public initializer {
        // Initializers
        __Context_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ERC165_init();
        __AccessControl_init();
        __ERC721_init("Steer Strategy", "STR_SRTGY");
        __ERC721Enumerable_init();
        __Pausable_init();
        __ERC721Pausable_init();
        __ERC721URIStorage_init();

        // Assign roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(GOVERNANCE_ROLE, _msgSender());

        // Setup the registry base url for the offchain protocol
        // this is used to create namespaced networks
        _baseTokenURI = registry;
        maxMaxGasPerAction = 15_000_000; // 15 million by default
    }

    /// @dev Create NFT for execution bundle
    /// @param strategyName The name of the strategy.
    /// @param execBundle The IPFS reference of the execution bundle.
    /// @param maxGasCost The maximum gas cost of the strategy.
    /// @param maxGasPerAction The maximum gas per action of the strategy, in terms of wei / gas.
    /// @return newStrategyTokenId as the token id of the new NFT.
    function createStrategy(
        address strategyCreator,
        string calldata strategyName,
        string calldata execBundle,
        uint128 maxGasCost,
        uint128 maxGasPerAction
    ) external returns (uint256 newStrategyTokenId) {
        // Check if the strategy is already registered
        // This occurs when the bundle has the same CID as a previously registered bundle
        bytes32 hashOfExecBundle = keccak256(abi.encodePacked(execBundle));
        require(hashOfExecBundle != hashedEmptyString, "Empty");
        require(
            keccak256(abi.encodePacked(strategies[execBundle].execBundle)) !=
                hashOfExecBundle,
            "Exists"
        );
        // Validate gas config
        require(
            maxGasPerAction <= maxMaxGasPerAction,
            "maxGasPerAction too high"
        );

        // Mint a new token to the current sender
        newStrategyTokenId = mint(strategyCreator, execBundle);

        // Utilizing the CID of the bundle we map the CID to a struct of RegisteredStrategy
        // We use the bundle hash instead of the token ID because this is helpful for the offchain protocol
        strategies[execBundle] = IStrategyRegistry.RegisteredStrategy({
            id: newStrategyTokenId,
            name: strategyName,
            owner: strategyCreator,
            execBundle: execBundle,
            maxGasCost: maxGasCost,
            maxGasPerAction: maxGasPerAction
        });

        // To help with enumeration we also map the token ID to the CID
        tokenIdToExecBundle[newStrategyTokenId] = execBundle;

        // Emit StrategyCreated event once a strategy is created
        emit StrategyCreated(
            strategyCreator,
            newStrategyTokenId,
            strategyName
        );
    }

    /// @dev Get the base URI
    /// @return The base URI of the registry
    /// @dev This is an internal function
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Get the base URI
     * @return The base URI of the registry
     */
    function baseURI() external view returns (string memory) {
        return _baseURI();
    }

    /**
     * @dev Creates a new token for `to`. Its token ID will be automatically
     * assigned (and available on the emitted {IERC721-Transfer} event), and the token
     * URI autogenerated based on the base URI passed at construction.
     *
     * See {ERC721-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(
        address recipient,
        string calldata bundle
    ) private returns (uint256) {
        uint256 newStrategyId = _tokenIdTracker.current();
        _mint(recipient, newStrategyId);
        _setTokenURI(newStrategyId, bundle);
        _tokenIdTracker.increment();
        return newStrategyId;
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "ERC721PresetMinterPauserAutoId: must have pauser role to pause"
        );
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC721Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "ERC721PresetMinterPauserAutoId: must have pauser role to unpause"
        );
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    )
        internal
        override(
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable,
            ERC721PausableUpgradeable
        )
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            AccessControlUpgradeable,
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
        return _baseURI();
    }

    function _burn(
        uint256 tokenId
    ) internal override(ERC721URIStorageUpgradeable, ERC721Upgradeable) {
        super._burn(tokenId);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @dev Get the strategy details by tokenId
    /// @param tokenId The token id of the strategy
    /// @return The details of the strategy
    function getRegisteredStrategy(
        uint256 tokenId
    ) public view returns (IStrategyRegistry.RegisteredStrategy memory) {
        return strategies[tokenIdToExecBundle[tokenId]];
    }

    /// @dev Set the gas parameters for a given strategy
    /// @param _tokenId The token id of the strategy
    /// @param _maxGasCost The maximum gas cost of the strategy
    /// @param _maxGasPerAction The maximum gas per action of the strategy
    function setGasParameters(
        uint256 _tokenId,
        uint128 _maxGasCost,
        uint128 _maxGasPerAction
    ) external {
        // Only the owner of the strategy is the only one who can set the gas parameters
        require(
            msg.sender == ownerOf(_tokenId),
            "Only strategy owner can set gas parameters"
        );

        // Validate gas config
        require(
            _maxGasPerAction <= maxMaxGasPerAction,
            "maxGasPerAction too high"
        );

        // Retrieve the current strategy details
        IStrategyRegistry.RegisteredStrategy storage strategy = strategies[
            tokenIdToExecBundle[_tokenId]
        ];

        // Set the gas parameters
        strategy.maxGasCost = _maxGasCost;
        strategy.maxGasPerAction = _maxGasPerAction;
    }

    function setMaxMaxGasPerAction(
        uint256 _maxMaxGasPerAction
    ) external onlyOwner {
        require(_maxMaxGasPerAction >= 15_000_000, "Invalid");
        maxMaxGasPerAction = _maxMaxGasPerAction;
    }
}

