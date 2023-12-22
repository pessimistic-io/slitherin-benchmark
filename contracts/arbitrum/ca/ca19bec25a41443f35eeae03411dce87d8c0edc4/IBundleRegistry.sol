// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.12;

interface IBundleRegistry {
    // Need to update contract!
    // Data Source Adapter
    // source: Source name, example: TheGraph
    // host: Host url or ip, example: https://api.thegraph.com/subgraphs/name/uniswap/uniswap-v3
    // output: The output type of the adapter, example: OHLC, OHLCV, SingleValue, etc.
    // bundle: (cid example: QmVj...DAwMA)
    // active: determines if the adapter is active or not, allows for inactive sources to be deprecated, vaults can pause based on this
    struct DataSourceAdapter {
        string bundle;
        string source;
        string host;
        string output;
        string info;
        bool active;
        address author;
    }

    event BundleRegistered(
        bytes32 hash,
        string bundle,
        string host,
        string source,
        string output,
        string infoHash,
        bool active,
        address creator
    );

    event BundleStateChange(bytes32 hash, bool toggle);

    /// @dev Registers an execution bundle, printing an NFT and mapping to execution bundle and host.
    /// @param _bundle the bundle of the transformation module.
    /// @param _source The host of the transformation module source (e.g. "Uniswap")
    /// @param _host The host of the transformation module source (e.g. "Uniswap")
    /// @param _output The output type of the adapter, example: OHLC, OHLCV, SingleValue, etc.
    /// @param _active determines if the adapter is active or not, allows for inactive sources to be deprecated, vaults can pause based on this
    function register(
        string memory _bundle,
        string memory _source,
        string memory _host,
        string memory _output,
        string memory _infoHash,
        bool _active
    ) external;

    /// @dev Pauses the registeration of bundles
    function pause() external;

    function setAdapterState(bytes32 _adapter, bool _remainActive) external;
}

