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
import "./ERC165CheckerUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./CurrencyTransferLib.sol";
import "./AspenERC721DropFactory.sol";
import "./AspenERC1155DropFactory.sol";
import "./AspenPaymentSplitterFactory.sol";
import "./BaseAspenDeployerV1.sol";
import "./AspenERC1155DropDelegateLogicFactory.sol";
import "./AspenERC721DropDelegateLogicFactory.sol";

contract AspenDeployer is Initializable, UUPSUpgradeable, AccessControlUpgradeable, BaseAspenDeployerV1 {
    AspenERC721DropFactory drop721Factory;
    AspenERC1155DropFactory drop1155Factory;
    AspenPaymentSplitterFactory paymentSplitterFactory;
    AspenERC1155DropDelegateLogicFactory drop1155DelegateLogicFactory;
    AspenERC721DropDelegateLogicFactory drop721DelegateLogicFactory;

    using ERC165CheckerUpgradeable for address;

    uint256 deploymentFee;
    address payable public feeReceiver;

    error IllegalVersionUpgrade(
        uint256 existingMajorVersion,
        uint256 existingMinorVersion,
        uint256 existingPatchVersion,
        uint256 newMajorVersion,
        uint256 newMinorVersion,
        uint256 newPatchVersion
    );

    error ImplementationNotVersioned(address implementation);
    error DeploymentFeeAlreadySet(uint256 existingFee);
    error FeeReceiverAlreadySet(address existingReceiver);

    function initialize(
        AspenERC721DropFactory _drop721Factory,
        AspenERC1155DropFactory _drop1155Factory,
        AspenPaymentSplitterFactory _paymentSplitterFactory,
        AspenERC1155DropDelegateLogicFactory _drop1155DelegateLogicFactory,
        AspenERC721DropDelegateLogicFactory _drop721DelegateLogicFactory,
        uint256 _deploymentFee,
        address _feeReceiver
    ) public virtual initializer {
        drop721Factory = _drop721Factory;
        drop1155Factory = _drop1155Factory;
        paymentSplitterFactory = _paymentSplitterFactory;
        drop1155DelegateLogicFactory = _drop1155DelegateLogicFactory;
        drop721DelegateLogicFactory = _drop721DelegateLogicFactory;
        deploymentFee = _deploymentFee;
        feeReceiver = payable(_feeReceiver);

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// @dev See ERC 165
    /// NOTE: Due to this function being overridden by 2 different contracts, we need to explicitly specify the interface here
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(BaseAspenDeployerV1, AccessControlUpgradeable)
        returns (bool)
    {
        return
            BaseAspenDeployerV1.supportsInterface(interfaceId) ||
            AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    /// ================================
    /// ========== Owner Only ==========
    /// ================================
    function reinitialize(
        AspenERC721DropFactory _drop721Factory,
        AspenERC1155DropFactory _drop1155Factory,
        AspenPaymentSplitterFactory _paymentSplitterFactory,
        AspenERC1155DropDelegateLogicFactory _drop1155DelegateLogicFactory,
        AspenERC721DropDelegateLogicFactory _drop721DelegateLogicFactory
    ) public virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        drop721Factory = _drop721Factory;
        drop1155Factory = _drop1155Factory;
        paymentSplitterFactory = _paymentSplitterFactory;
        drop1155DelegateLogicFactory = _drop1155DelegateLogicFactory;
        drop721DelegateLogicFactory = _drop721DelegateLogicFactory;
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        (uint256 major, uint256 minor, uint256 patch) = this.implementationVersion();
        if (!newImplementation.supportsInterface(type(IAspenVersionedV2).interfaceId)) {
            revert ImplementationNotVersioned(newImplementation);
        }
        (uint256 newMajor, uint256 newMinor, uint256 newPatch) = IAspenVersionedV2(newImplementation)
            .implementationVersion();
        // Do not permit a breaking change via an UUPS proxy upgrade - this requires a new proxy. Otherwise, only allow
        // minor/patch versions to increase
        if (major != newMajor || minor > newMinor || (minor == newMinor && patch > newPatch)) {
            revert IllegalVersionUpgrade(major, minor, patch, newMajor, newMinor, newPatch);
        }
    }

    /// @dev This functions updates the deployment fee and fee receiver address.
    /// @param _newDeploymentFee The new deployment fee
    /// @param _newFeeReceiver The new fee receiver address
    function updateDeploymentFeeDetails(uint256 _newDeploymentFee, address _newFeeReceiver)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        feeReceiver = payable(_newFeeReceiver);
        deploymentFee = _newDeploymentFee;
    }

    function getDeploymentFeeDetails() public view returns (uint256 _deploymentFee, address _feeReceiver) {
        _deploymentFee = deploymentFee;
        _feeReceiver = feeReceiver;
    }

    /// @dev This function disables the deployment fee by setting the fee value to 0.
    function disableDeploymentFee() public onlyRole(DEFAULT_ADMIN_ROLE) {
        deploymentFee = 0;
    }

    /// ================================
    /// ========== Deployments =========
    /// ================================
    function deployAspenERC721Drop(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _saleRecipient,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        string memory _userAgreement,
        uint128 _platformFeeBps,
        address _platformFeeRecipient
    ) external payable override returns (IAspenERC721DropV1) {
        AspenERC721DropDelegateLogic drop721DelegateLogic = _deployDrop721DelegateLogic();
        AspenERC721Drop newContract = drop721Factory.deploy(
            _defaultAdmin,
            _name,
            _symbol,
            _contractURI,
            _trustedForwarders,
            _saleRecipient,
            _royaltyRecipient,
            _royaltyBps,
            _userAgreement,
            _platformFeeBps,
            _platformFeeRecipient,
            address(drop721DelegateLogic)
        );

        (uint256 major, uint256 minor, uint256 patch) = newContract.implementationVersion();
        string memory interfaceId = newContract.implementationInterfaceId();
        _payDeploymentFee();
        emit AspenInterfaceDeployed(address(newContract), major, minor, patch, interfaceId);
        return IAspenERC721DropV1(address(newContract));
    }

    function deployAspenERC1155Drop(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _saleRecipient,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        string memory _userAgreement,
        uint128 _platformFeeBps,
        address _platformFeeRecipient
    ) external payable override returns (IAspenERC1155DropV1) {
        AspenERC1155DropDelegateLogic drop1155DelegateLogic = _deployDrop1155DelegateLogic();
        AspenERC1155Drop newContract = drop1155Factory.deploy(
            _defaultAdmin,
            _name,
            _symbol,
            _contractURI,
            _trustedForwarders,
            _saleRecipient,
            _royaltyRecipient,
            _royaltyBps,
            _userAgreement,
            _platformFeeBps,
            _platformFeeRecipient,
            address(drop1155DelegateLogic)
        );

        (uint256 major, uint256 minor, uint256 patch) = newContract.implementationVersion();
        string memory interfaceId = newContract.implementationInterfaceId();
        _payDeploymentFee();
        emit AspenInterfaceDeployed(address(newContract), major, minor, patch, interfaceId);
        return IAspenERC1155DropV1(address(newContract));
    }

    function deployAspenPaymentSplitter(address[] memory payees, uint256[] memory shares_)
        external
        override
        returns (IAspenPaymentSplitterV1)
    {
        AspenPaymentSplitter newContract = paymentSplitterFactory.deploy(payees, shares_);
        string memory interfaceId = newContract.implementationInterfaceId();
        (uint256 major, uint256 minor, uint256 patch) = newContract.implementationVersion();
        emit AspenInterfaceDeployed(address(newContract), major, minor, patch, interfaceId);
        return IAspenPaymentSplitterV1(address(newContract));
    }

    /// ================================
    /// =========== Versioning =========
    /// ================================
    function aspenERC721DropVersion()
        external
        view
        override
        returns (
            uint256 major,
            uint256 minor,
            uint256 patch
        )
    {
        return drop721Factory.implementationVersion();
    }

    function aspenERC1155DropVersion()
        external
        view
        override
        returns (
            uint256 major,
            uint256 minor,
            uint256 patch
        )
    {
        return drop1155Factory.implementationVersion();
    }

    function aspenPaymentSplitterVersion()
        external
        view
        override
        returns (
            uint256 major,
            uint256 minor,
            uint256 patch
        )
    {
        return paymentSplitterFactory.implementationVersion();
    }

    /// ================================
    /// =========== Features ===========
    /// ================================
    function aspenERC721DropFeatures() public view override returns (string[] memory features) {
        return drop721Factory.implementation().supportedFeatures();
    }

    function aspenERC1155DropFeatures() public view override returns (string[] memory features) {
        return drop1155Factory.implementation().supportedFeatures();
    }

    function aspenPaymentSplitterFeatures() external view override returns (string[] memory features) {
        return paymentSplitterFactory.implementation().supportedFeatures();
    }

    /// ================================
    /// ======= Internal Methods =======
    /// ================================
    function _deployDrop721DelegateLogic() internal returns (AspenERC721DropDelegateLogic) {
        return drop721DelegateLogicFactory.deploy();
    }

    function _deployDrop1155DelegateLogic() internal returns (AspenERC1155DropDelegateLogic) {
        return drop1155DelegateLogicFactory.deploy();
    }

    /// @dev This function checks if both the deployment fee and fee receiver address are set.
    ///     If they are, then it pays the deployment fee to the fee receiver.
    function _payDeploymentFee() internal {
        if (deploymentFee > 0 && feeReceiver != address(0)) {
            CurrencyTransferLib.safeTransferNativeToken(feeReceiver, deploymentFee);
        }
    }

    /// ================================
    /// ======== Miscellaneous =========
    /// ================================
    // Concrete implementation semantic version - provided for completeness but not designed to be the point of dispatch
    function minorVersion() public pure virtual override returns (uint256 minor, uint256 patch) {
        minor = 0;
        patch = 0;
    }
}

