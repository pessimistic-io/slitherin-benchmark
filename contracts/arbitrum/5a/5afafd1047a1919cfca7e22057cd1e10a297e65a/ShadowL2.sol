// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.6.11;

// Needed for returning UserScore struct as array w/ 0.6.
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./AccessControl.sol";
import "./ArbSys.sol";
import "./AddressAliasHelper.sol";
import "./ERC721S.sol";

contract ShadowL2 is ERC721S, Ownable, AccessControl {
    ArbSys constant arbsys = ArbSys(100);
    address public l1Target;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct UserScore {
        address user;
        uint256 score;
        uint256 tokenId;
    }

    // Mapping from token ID to L2 owner address
    UserScore[] private _userScores;

    // Mapping address to registered event dates
    mapping(address => uint256[]) private _userRegistration;

    event L2ToL1TxCreated(uint256 indexed withdrawalId);

    constructor(
        string memory _name, 
        string memory _symbol
        // address _l1Target
    ) public ERC721S(_name, _symbol) {
        // l1Target = _l1Target;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Assign manager role to allow setting scores. Will only be callable by role admins.
    function grantManagerRole(address _manager) public {
        grantRole(MANAGER_ROLE, _manager);
    }

    function updateL1Target(address _l1Target) public onlyOwner {
        l1Target = _l1Target;
    }

    /// @notice only l1Target can update greeting
    function setShadow(address _rootOwner, address _shadowOwner, uint256 _tokenId) public override {
        // To check that message came from L1, we check that the sender is the L1 contract's L2 alias.
        require(
            msg.sender == AddressAliasHelper.applyL1ToL2Alias(l1Target),
            "Shadow only updateable by L1"
        );
        ERC721S.setShadow(_rootOwner, _shadowOwner, _tokenId);
    }

    function setUserScore(address _user, uint256 _userScore, uint256 _tokenId) public {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a Manager");
        _userScores.push(UserScore(_user, _userScore, _tokenId));
    }

    function userScores() public view returns(UserScore[] memory) {
        return _userScores;
    }

    function registerUser(address _user, uint256 _registrationDate) public {
        require(hasRole(MANAGER_ROLE, msg.sender), "Caller is not a Manager");

        _userRegistration[_user].push(_registrationDate);
    }

     function userRegistered(address _user) public view returns(uint256[] memory) {
        return _userRegistration[_user];
    }
}
