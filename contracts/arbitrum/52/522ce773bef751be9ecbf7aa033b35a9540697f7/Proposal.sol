// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./Strings.sol";
import "./Ownable.sol";
import "./EIP712.sol";
import "./ECDSA.sol";
import "./ERC721.sol";
import "./ERC721URIStorage.sol";
import "./IEmployeeNFT.sol";

contract Pet2DAOProposal is Ownable, ERC721URIStorage, EIP712 {
    string private constant SIGNING_DOMAIN = "Level-Voucher";
    string private constant SIGNATURE_VERSION = "1";

    struct Proposal {
        address creator;
        string contentURL;
        uint32[] approvers;
        bool isAccepted;
        bool isPublic;
    }

    struct LevelVoucher {
        uint32 nftId;
        uint256 proposalId;
        uint256 level;
        bool isAccepted;
        bytes signature;
    }

    IEmployeeNFT public employeeNFT;
    Proposal[] private _proposals;
    uint256[] private _approvedProposalIds;

    constructor(address _employeeNFT)
        ERC721("Employee NFT", "Employee") EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
            employeeNFT = IEmployeeNFT(_employeeNFT);
        }

    modifier onlyAdmin() {
        require(employeeNFT.isAdmin(msg.sender), "Restricted to admins.");
        _;
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize)
        internal
        override(ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == address(0), "You can't transfer this NFT.");
        super._transfer(from, to, tokenId);
    }

    function _mint(
        uint256 _tokenId,
        address to,
        string memory _tokenURI
    ) internal {
        _safeMint(to, _tokenId);
        _setTokenURI(_tokenId, _tokenURI);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function createProposal(string memory _contentURI, uint32[] calldata _approvers, bool _isPublic) public {
        _proposals.push(Proposal(msg.sender, _contentURI, _approvers, false, _isPublic));
    }

    function approveProposal(uint256 index, LevelVoucher[] calldata vouchers, bool mintingNFT) external {
        require(
            _proposals[index].isAccepted == false,
            "This proposal is already accepted"
        );
        Proposal storage _proposal = _proposals[index];
        uint32[] memory _approvers = _proposal.approvers;
        if (_approvers.length == 1) {
            if (employeeNFT.ownerOf(uint256(_approvers[0])) != msg.sender) revert("No approver");
            _proposal.isAccepted = true;
            _approvedProposalIds.push(index);
            if (mintingNFT) _mint(index, msg.sender, _proposal.contentURL);
            return;
        }
        for(uint256 i = 0; i < _approvers.length - 1; i++) {
            address signer = _verify(vouchers[i]);
            if (signer != employeeNFT.ownerOf(uint256(vouchers[i].nftId)) || vouchers[i].nftId != _approvers[i]) revert("Invalid Voucher Address");
            if (index != vouchers[i].proposalId) revert("Invalid Proposal Id");
            if (i != vouchers[i].level) revert("Invalid Level");
            if (i != _approvers.length - 1) {
                if (!vouchers[i].isAccepted) revert("Proposal is already rejected");
            } else {
                _proposal.isAccepted = true;
                _approvedProposalIds.push(index);
                if (mintingNFT) _mint(index, msg.sender, _proposal.contentURL);
            }
        }
    }

    function deleteProposal(uint index) public onlyAdmin {
        require(index < _proposals.length, "Invalid Index");
        _proposals[index] = _proposals[_proposals.length - 1];
        _proposals.pop();
    }

    function getAllProposal(
        uint256 start,
        uint256 end
    ) public view returns (Proposal[] memory) {
        require(end <= _proposals.length, "Invalid Index");
        Proposal[] memory proposalSlice = new Proposal[](end - start);
        for (uint256 i = start; i < end; i++) {
            proposalSlice[i] = _proposals[i];
        }
        return proposalSlice;
    }

    function getApprovedProposals(
        uint256 start,
        uint256 end
    ) public view returns (Proposal[] memory) {
        require(end <= _approvedProposalIds.length, "Invalid Index");
        Proposal[] memory proposalSlice = new Proposal[](end - start);
        for (uint256 i = start; i < end; i++) {
            proposalSlice[i] = _proposals[_approvedProposalIds[i]];
        }
        return proposalSlice;
    }

    function getProposalCount() external view returns (uint256) {
        return _proposals.length;
    }

    function getApprovedProposalCount() external view returns (uint256) {
        return _approvedProposalIds.length;
    }

    function setEmployeeNFT(address _employeeNFT) external onlyAdmin {
        employeeNFT = IEmployeeNFT(_employeeNFT);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _hash(LevelVoucher calldata voucher) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
            keccak256("LevelVoucher(uint32 nftId,uint256 proposalId,uint256 level,bool isAccepted)"),
            voucher.nftId,
            voucher.proposalId,
            voucher.level,
            voucher.isAccepted
        )));
    }

    function _verify(LevelVoucher calldata voucher) internal view returns (address) {
        bytes32 digest = _hash(voucher);
        return ECDSA.recover(digest, voucher.signature);
    }
}

