//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusNebulaRegistry.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸         🛸                              🛸          .                    
     🛸   ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .    🛸*     ░░██████  ░░██████   .    🛸                     🛰️            -----=========*                 
                       ░░░░░░    ░░░░░░                                               🛸  ⠀
           .                            .       .             🛰️         .                          
    
        CYGNUS NEBULA REGISTRY - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebulaRegistry} from "./ICygnusNebulaRegistry.sol";
import {ICygnusNebula} from "./ICygnusNebula.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

// Libraries

// Interfaces
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IERC20} from "./IERC20.sol";

/**
 *  @title  CygnusNebulaRegistry
 *  @author CygnusDAO
 *  @notice Registry of all nebulas deployed by CygnusDAO. A nebula is a contract which contains the logic to
 *          price specific Liquidity Tokens. For example, Balancer Weighted Pools requires different logic than
 *          UniswapV2 pairs to price the liquidity token, so we must deploy separate logic for each. A nebula
 *          oracle is a unique LP oracle within the nebula.
 *
 *          Each nebula we deploy must have this registry's address as the registry is the only one that can
 *          initialize a specific Liquidity Token in the nebula.
 *
 *          At the time of pool deployment, the hangar18 contract checks this contract to see if the liquidity
 *          token has been added to the registry via `getLPTokenNebulaAddress`. If it hasn't, then the pool cannot
 *          be deployed as the collateral cannot be priced.
 */
contract CygnusNebulaRegistry is ICygnusNebulaRegistry, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Storage mapping for LP Token => Nebula address
     */
    mapping(address => address) internal lpNebulas;

    /**
     *  @notice Storage mapping for Nebula address => Nebula struct
     */
    mapping(address => CygnusNebula) internal nebulas;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    CygnusNebula[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address[] public allLPTokenPairs;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    string public override name = "Cygnus: Nebula Registry";

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    string public override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address public override admin;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Oracle registry
     */
    constructor() {
        // Assign the admin
        admin = msg.sender;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for admin control only 👽
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admin control only 👽
     */
    function isCygnusAdmin() internal view {
        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) revert CygnusNebula__SenderNotAdmin();
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function allNebulasLength() public view override returns (uint256) {
        // Total initialized nebulas
        return allNebulas.length;
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function allLPTokenPairsLength() public view override returns (uint256) {
        // Total initialized LP Token pairs
        return allLPTokenPairs.length;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getNebula(address nebula) external view override returns (CygnusNebula memory) {
        // Return the nebula struct for this `_nebula`
        return nebulas[nebula];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebula(address lpTokenPair) external view override returns (CygnusNebula memory) {
        // Get the stored nebula for `lpTokenPair`
        address nebula = lpNebulas[lpTokenPair];

        // Return the nebula struct for this `lpTokenPair`
        return nebulas[nebula];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebulaAddress(address lpTokenPair) external view override returns (address) {
        // Return the address of the nebula for this `lpTokenPair`
        // If not set then returns zero address
        return lpNebulas[lpTokenPair];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebulaOracle(address lpTokenPair) external view override returns (ICygnusNebula.NebulaOracle memory) {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the oracle struct
        return ICygnusNebula(nebula).getNebulaOracle(lpTokenPair);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenPriceUsd(address lpTokenPair) external view override returns (uint256) {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the price of the LP in the oracle`s denomination token (in our case USDC)
        // IMPORTANT: Do not use this in any important contract since the oracle never does safety checks,
        // such as assuring price != 0, etc.
        return ICygnusNebula(nebula).lpTokenPriceUsd(lpTokenPair);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenInfo(
        address lpTokenPair
    )
        external
        view
        override
        returns (
            IERC20[] memory tokens,
            uint256[] memory prices,
            uint256[] memory reserves,
            uint256[] memory tokenDecimals,
            uint256[] memory reservesUsd
        )
    {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the current info of the LP
        // IMPORTANT: Do not use this on-chain, this function is for convention and reporting purposes only
        return ICygnusNebula(nebula).lpTokenInfo(lpTokenPair);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function createNebulaOracle(
        uint256 nebulaId,
        address lpTokenPair,
        AggregatorV3Interface[] calldata aggregators,
        bool isOverride
    ) external override cygnusAdmin {
        // Get nebula address
        CygnusNebula storage nebula = allNebulas[nebulaId];

        // Initialize nebula. Will revert if it has already been initialized and we are outside grace period
        ICygnusNebula(nebula.nebulaAddress).initializeNebulaOracle(lpTokenPair, aggregators);

        // If this is the first time we initialize this oracle;
        // Account for cases where we modify the oracle during grace period
        if (lpNebulas[lpTokenPair] == address(0)) allLPTokenPairs.push(lpTokenPair);

        // If we are not overriding then we add oracle to nebula (this is done for quick info purposes)
        if (!isOverride) nebula.totalOracles++;

        // Map LP Token => Nebula address
        // This is intentinally left outside of the above if statement. If we need to re-deploy an oracle
        // and initialize lp tokens, then we override the `lpNebulas` mapping, and future shuttles
        // deployed by the factory will use this new oracle instead.
        lpNebulas[lpTokenPair] = nebula.nebulaAddress;

        // Map Nebula address => Nebula struct
        nebulas[nebula.nebulaAddress] = nebula;
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function createNebula(address _nebula) external override cygnusAdmin {
        /// @custom:error NebulaAlreadyCreated
        if (nebulas[_nebula].createdAt != 0) revert CygnusNebula__NebulaAlreadyCreated();

        // Create new nebula since it passed checks
        CygnusNebula memory nebula = CygnusNebula({
            name: ICygnusNebula(_nebula).name(),
            nebulaAddress: _nebula,
            nebulaId: allNebulasLength(),
            totalOracles: 0,
            createdAt: block.timestamp
        });

        // Add nebula to array
        allNebulas.push(nebula);

        // Add nebula to mapping
        nebulas[_nebula] = nebula;

        /// @custom:event NewNebulaOracle
        emit NewNebulaOracle(_nebula, nebula.nebulaId);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function setRegistryPendingAdmin(address newPendingAdmin) external override cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == admin) revert CygnusNebula__AdminAlreadySet();

        // Assign address of the requested admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewNebulaPendingAdmin(admin, newPendingAdmin);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-pending-admin
     */
    function acceptRegistryAdmin() external override {
        /// @custom:error SenderNotPendingAdmin Avoid if sender is not pending admin
        if (msg.sender != pendingAdmin) revert CygnusNebula__SenderNotPendingAdmin();

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Assign new admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewOracleAdmin
        emit NewNebulaAdmin(oldAdmin, admin);
    }
}

