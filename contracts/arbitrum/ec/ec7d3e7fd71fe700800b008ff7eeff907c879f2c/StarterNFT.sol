// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC721.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";

/// @title HonestWork Starter NFT
/// @author @takez0_o
/// @notice Starter Membership NFT's to be used in the platform
contract StarterNFT is ERC721, Ownable {
    struct Payment {
        address token;
        uint256 amount;
        uint256 ambassadorPercentage;
    }
    string public baseuri;
    uint256 public cap = 10000;
    uint256 public id = 1;
    bool public paused = false;
    bool public single_asset = true;
    Payment public payment;
    bytes32 public whitelistRoot;
    mapping(address ambassador => uint256 profit) public profits;
    uint256 hwProfit = 0;

    event Mint(uint256 id, address user);
    event AmbassadorMint(uint256 id, address user, address ambassador);

    constructor(
        string memory _baseuri,
        address _token,
        uint256 _amount,
        uint256 _ambassadorPercentage
    ) ERC721("HonestWork Starter", "HWS") {
        baseuri = _baseuri;
        payment = Payment(_token, _amount, _ambassadorPercentage);
        _mint(msg.sender, 0);
    }

    //-----------------//
    //  admin methods  //
    //-----------------//

    function setBaseUri(string memory _baseuri) external onlyOwner {
        baseuri = _baseuri;
    }

    function setCap(uint256 _cap) external onlyOwner {
        cap = _cap;
    }

    function setSingleAsset(bool _single_asset) external onlyOwner {
        single_asset = _single_asset;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function setPayment(address _token, uint256 _amount, uint256 _ambassadorPercentage) external onlyOwner {
        payment = Payment(_token, _amount, _ambassadorPercentage);
    }

    function setWhitelistRoot(bytes32 _root) external onlyOwner {
        whitelistRoot = _root;
    }

    function withdraw() external onlyOwner {
      IERC20(payment.token).transfer(msg.sender, hwProfit);
    }

    //--------------------//
    //  internal methods  //
    //--------------------//

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _whitelistLeaf(address _address) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_address));
    }

    function _verify(
        bytes32 _leaf,
        bytes32 _root,
        bytes32[] memory _proof
    ) internal pure returns (bool) {
        return MerkleProof.verify(_proof, _root, _leaf);
    }

    //--------------------//
    //  mutative methods  //
    //--------------------//

    function mint() external whenNotPaused {
        require(id < cap, "cap reached");
        IERC20(payment.token).transferFrom(
            msg.sender,
            address(this),
            payment.amount
        );
        _mint(msg.sender, id);
        emit Mint(id, msg.sender);
        hwProfit += payment.amount;
        id++;
    }

    function ambassadorMint(address _ambassador, bytes32[] calldata _proof) external whenNotPaused {
        require(id < cap, "cap reached");
        require(
            _verify(_whitelistLeaf(_ambassador), whitelistRoot, _proof),
            "Invalid merkle proof"
        );
        IERC20(payment.token).transferFrom(
            msg.sender,
            address(this),
            payment.amount
        );
        _mint(msg.sender, id);
        emit AmbassadorMint(id, msg.sender, _ambassador);
        uint256 profit = payment.amount * payment.ambassadorPercentage / 100;
        profits[_ambassador] += profit;
        hwProfit += payment.amount - profit;
        id++;
    }

    function ambassadorClaim() external {
        require(profits[msg.sender] > 0, "No profits to claim");
        IERC20(payment.token).transfer(msg.sender, profits[msg.sender]);
        profits[msg.sender] = 0;
    }

    //----------------//
    //  view methods  //
    //----------------//

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(ERC721)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    function tokenURI(uint256 _tokenid)
        public
        view
        override
        returns (string memory)
    {
        if (single_asset) {
            return string(abi.encodePacked(baseuri, "1"));
        } else {
            return string(abi.encodePacked(baseuri, _toString(_tokenid)));
        }
    }

    //----------------//
    //   modifiers    //
    //----------------//

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }
}

