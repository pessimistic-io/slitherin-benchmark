// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

// Proxy Support
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./PausableUpgradeable.sol";
import { IBundleRegistry } from "./IBundleRegistry.sol";

contract BundleRegistry is
    IBundleRegistry,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    // Storage

    mapping(bytes32 => DataSourceAdapter) public bundles;

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        __Pausable_init();
    }

    /// @dev Registers an execution bundle, making data accessible to nodes.
    ///      Once registered, each bundle is immutable.
    ///      Only the contract owner can change it, and they can only
    ///      deactivate/reactivate it if necessary.
    /// @param _bundle The bundle of the transformation module.
    /// @param _source The source of the transformation module source (e.g. "The Graph" or "Twitter")
    /// @param _host The host of the transformation module source (e.g. "Uniswap" or "@random-twitter-username")
    /// @param _output The output type of the adapter, example: OHLC, OHLCV, SingleValue, etc.
    /// @param _active Determines if the adapter is active or not, allows for inactive sources
    ///                to be deprecated, vaults can pause based on this
    function register(
        string memory _bundle,
        string memory _source,
        string memory _host,
        string memory _output,
        string memory _infoHash,
        bool _active
    ) external whenNotPaused {
        require(isIPFS(_bundle), "Bundle must be an IPFS CID hash");

        bytes32 bundleHash = keccak256(
            abi.encode(_bundle, _source, _host, _output)
        );

        // Check that bundle does not yet have an author--proxy
        // to check whether the bundle was already registered.

        require(
            bundles[bundleHash].author == address(0),
            "Bundle already registered"
        );

        // Record bundle
        bundles[bundleHash] = DataSourceAdapter({
            bundle: _bundle,
            source: _source,
            host: _host,
            output: _output,
            info: _infoHash,
            active: _active,
            author: _msgSender()
        });

        // Emit the event that the bundle was created
        emit BundleRegistered(
            bundleHash,
            _bundle,
            _host,
            _source,
            _output,
            _infoHash,
            _active,
            msg.sender
        );
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    /// @dev onlyOwner function to deprecate (or reactivate) an existing adapter.
    /// @param _adapter The key of the adapter to pause.
    /// @param _remainActive Whether to pause or unpause; false to pause.
    function setAdapterState(
        bytes32 _adapter,
        bool _remainActive
    ) external onlyOwner {
        bundles[_adapter].active = _remainActive;
        emit BundleStateChange(_adapter, _remainActive);
    }

    /// @dev Checks if the passed string is a IPFS link or not.
    /// @param source String that needs to checked.
    /// @return true if the string passed is IPFS, else it will return false.
    function isIPFS(string memory source) internal pure returns (bool) {
        bytes memory sourceToBytes = bytes(source);
        require(sourceToBytes.length == 46, "Length");
        bytes memory firstChar = new bytes(1);
        bytes memory secondChar = new bytes(1);
        bytes memory lastChar = new bytes(1);
        firstChar[0] = sourceToBytes[0];
        secondChar[0] = sourceToBytes[1];
        lastChar[0] = sourceToBytes[45];
        return
            keccak256(firstChar) == keccak256(bytes("Q")) &&
            keccak256(secondChar) == keccak256(bytes("m")) &&
            (keccak256(lastChar) != keccak256(bytes("O")) &&
                keccak256(lastChar) != keccak256(bytes("I")) &&
                keccak256(lastChar) != keccak256(bytes("l")));
    }
}

