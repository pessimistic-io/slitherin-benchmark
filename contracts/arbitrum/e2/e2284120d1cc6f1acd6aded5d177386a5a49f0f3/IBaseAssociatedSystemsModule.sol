pragma solidity >=0.8.19;

/**
 * @title Module for connecting a system with other associated systems.
 * Associated systems become available to all system modules for communication and interaction,
 * but as opposed to inter-modular communications, interactions with associated systems will require the use of `CALL`.
 *
 * Associated systems can be managed or unmanaged.
 * - Managed systems are connected via a proxy, which means that their implementation can be updated,
 * and the system controls the execution context of the associated system. Example,
 * account token connected to the system, and controlled by the system.
 * - Unmanaged systems are just addresses tracked by the system, for which it has no control whatsoever.
 * Currently, we're not using these, however may consider using for interactions with external
 * instruments and exchanges (e.g. dated irs instrument).
 *
 * Furthermore, associated systems are typed in the AssociatedSystem utility library (See AssociatedSystem.sol):
 * - KIND_ERC721: A managed associated system specifically wrapping an ERC721 implementation.
 * - KIND_UNMANAGED: Any unmanaged associated system. (currently not supporting this)
 */
interface IBaseAssociatedSystemsModule {
    /**
     * @notice Emitted when an associated system is set.
     * @param kind The type of associated system (managed ERC721, etc - See the AssociatedSystem util).
     * @param id The bytes32 identifier of the associated system.
     * @param proxy The main external contract address of the associated system.
     * @param impl The address of the implementation of the associated system (if not behind a proxy, will equal `proxy`).
     */
    event AssociatedSystemSet(bytes32 indexed kind, bytes32 indexed id, address proxy, address impl);

    /**
     * @notice Emitted when the function you are calling requires an associated system, but it
     * has not been registered
     */
    error MissingAssociatedSystem(bytes32 id);

    /**
     * @notice Creates or initializes a managed associated ERC721 token.
     * @param id The bytes32 identifier of the associated system. If the id is new to the system,
     * it will create a new proxy for the associated system.
     * @param name The token name that will be used to initialize the proxy.
     * @param symbol The token symbol that will be used to initialize the proxy.
     * @param uri The token uri that will be used to initialize the proxy.
     * @param impl The ERC721 implementation of the proxy.
     */
    function initOrUpgradeNft(bytes32 id, string memory name, string memory symbol, string memory uri, address impl)
        external;

    /**
     * @notice Retrieves an associated system.
     * @param id The bytes32 identifier used to reference the associated system.
     * @return addr The external contract address of the associated system.
     * @return kind The type of associated system (managed ERC721, etc - See the AssociatedSystem util).
     */
    function getAssociatedSystem(bytes32 id) external view returns (address addr, bytes32 kind);
}

