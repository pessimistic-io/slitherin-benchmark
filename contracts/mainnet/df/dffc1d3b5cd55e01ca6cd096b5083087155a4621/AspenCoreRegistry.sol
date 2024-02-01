// SPDX-License-Identifier: Apache-2.0

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                                                           //
//                      _'                    AAA                                                                                            //
//                    !jz_                   A:::A                                                                                           //
//                 ;Lzzzz-                  A:::::A                                                                                          //
//              '1zzzzxzz'                 A:::::::A                                                                                         //
//            !xzzzzzzi~                  A:::::::::A             ssssssssss   ppppp   ppppppppp       eeeeeeeeeeee    nnnn  nnnnnnnn        //
//         ;izzzzzzj^`                   A:::::A:::::A          ss::::::::::s  p::::ppp:::::::::p    ee::::::::::::ee  n:::nn::::::::nn      //
//              `;^.`````               A:::::A A:::::A       ss:::::::::::::s p:::::::::::::::::p  e::::::eeeee:::::een::::::::::::::nn     //
//              -;;;;;;;-              A:::::A   A:::::A      s::::::ssss:::::spp::::::ppppp::::::pe::::::e     e:::::enn:::::::::::::::n    //
//           .;;;;;;;_                A:::::A     A:::::A      s:::::s  ssssss  p:::::p     p:::::pe:::::::eeeee::::::e  n:::::nnnn:::::n    //
//         ;;;;;;;;`                 A:::::AAAAAAAAA:::::A       s::::::s       p:::::p     p:::::pe:::::::::::::::::e   n::::n    n::::n    //
//      _;;;;;;;'                   A:::::::::::::::::::::A         s::::::s    p:::::p     p:::::pe::::::eeeeeeeeeee    n::::n    n::::n    //
//            ;{jjjjjjjjj          A:::::AAAAAAAAAAAAA:::::A  ssssss   s:::::s  p:::::p    p::::::pe:::::::e             n::::n    n::::n    //
//         `+IIIVVVVVVVVI`        A:::::A             A:::::A s:::::ssss::::::s p:::::ppppp:::::::pe::::::::e            n::::n    n::::n    //
//       ^sIVVVVVVVVVVVVI`       A:::::A               A:::::As::::::::::::::s  p::::::::::::::::p  e::::::::eeeeeeee    n::::n    n::::n    //
//    ~xIIIVVVVVVVVVVVVVI`      A:::::A                 A:::::As:::::::::::ss   p::::::::::::::pp    ee:::::::::::::e    n::::n    n::::n    //
//  -~~~;;;;;;;;;;;;;;;;;      AAAAAAA                   AAAAAAAsssssssssss     p::::::pppppppp        eeeeeeeeeeeeee    nnnnnn    nnnnnn    //
//                                                                              p:::::p                                                      //
//                                                                              p:::::p                                                      //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             p:::::::p                                                     //
//                                                                             ppppppppp                                                     //
//                                                                                                                                           //
//  Website: https://aspenft.io/                                                                                                             //
//  Twitter: https://twitter.com/aspenft                                                                                                     //
//                                                                                                                                           //
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

pragma solidity ^0.8;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC165CheckerUpgradeable.sol";
import "./IUUPSUpgradeableErrors.sol";
import "./BaseAspenCoreRegistryV0.sol";
import "./PlatformFeeConfigUpgradeable.sol";
import "./OperatorFiltererConfig.sol";
import "./CoreRegistry.sol";

contract AspenCoreRegistry is
Initializable,
UUPSUpgradeable,
AccessControlUpgradeable,
CoreRegistry,
PlatformFeeConfigUpgradeable,
OperatorFiltererConfig,
BaseAspenCoreRegistryV0
{
    using ERC165CheckerUpgradeable for address;

    /// @dev Max basis points (bps) in Aspen platform.
    uint256 public constant MAX_BPS = 10_000;

    function initialize(address _platformFeeReceiver, uint16 _platformFeeBPS) public virtual initializer {
        __PlatformFeeConfig_init(_platformFeeReceiver, _platformFeeBPS);

        super._addOperatorFilterer(
            IOperatorFiltererDataTypesV0.OperatorFilterer(
                keccak256(abi.encodePacked("NO_OPERATOR")),
                "No Operator",
                address(0),
                address(0)
            )
        );

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        (uint256 major, uint256 minor, uint256 patch) = this.implementationVersion();
        if (!newImplementation.supportsInterface(type(ICedarVersionedV1).interfaceId)) {
            revert IUUPSUpgradeableErrorsV0.ImplementationNotVersioned(newImplementation);
        }
        (uint256 newMajor, uint256 newMinor, uint256 newPatch) = ICedarVersionedV1(newImplementation)
        .implementationVersion();
        // Do not permit a breaking change via an UUPS proxy upgrade - this requires a new proxy. Otherwise, only allow
        // minor/patch versions to increase
        if (major != newMajor || minor > newMinor || (minor == newMinor && patch > newPatch)) {
            revert IUUPSUpgradeableErrorsV0.IllegalVersionUpgrade(major, minor, patch, newMajor, newMinor, newPatch);
        }
    }

    /// @dev See ERC 165
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(BaseAspenCoreRegistryV0, AccessControlUpgradeable)
    returns (bool)
    {
        return
        super.supportsInterface(interfaceId) ||
        BaseAspenCoreRegistryV0.supportsInterface(interfaceId) ||
        AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    /// ===================================
    /// ========== Platform Fees ==========
    /// ===================================
    function setPlatformFees(address _newPlatformFeeReceiver, uint16 _newPlatformFeeBPS)
    public
    override(IPlatformFeeConfigV0, PlatformFeeConfigUpgradeable)
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        super.setPlatformFees(_newPlatformFeeReceiver, _newPlatformFeeBPS);
    }

    /// ========================================
    /// ========== Operator Filterers ==========
    /// ========================================
    function addOperatorFilterer(IOperatorFiltererDataTypesV0.OperatorFilterer memory _newOperatorFilterer)
    public
    override(IOperatorFiltererConfigV0, OperatorFiltererConfig)
    isValidOperatorConfig(_newOperatorFilterer)
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        super._addOperatorFilterer(_newOperatorFilterer);
    }

    function addContract(bytes32 _nameHash, address _addr)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    returns (bool result)
    {
        return super.addContract(_nameHash, _addr);
    }

    function addContractForString(string calldata _name, address _addr)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    returns (bool result)
    {
        return super.addContractForString(_name, _addr);
    }

    function setConfigContract(address _configContract, string calldata _version)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        super.setConfigContract(_configContract, _version);
    }

    function setDeployerContract(address _deployerContract, string calldata _version)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    {
        super.setDeployerContract(_deployerContract, _version);
    }

    // Concrete implementation semantic version - provided for completeness but not designed to be the point of dispatch
    function minorVersion() public pure virtual override returns (uint256 minor, uint256 patch) {
        minor = 0;
        patch = 0;
    }
}

