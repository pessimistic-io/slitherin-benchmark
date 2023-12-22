pragma solidity ^0.8.0;
// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./ECDSA.sol";
import "./EIP712.sol";
import "./ISecondLiveMedal.sol";

/**
 * @title SpaceStation
 * @author SecondLive Protocol
 *
 * Campaign contract 
    that allows privileged DAOs to initiate campaigns for members to 
    claim SecondLiveNFTs.
 */
contract SpaceStation is EIP712, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    bool private initialized;

    address public signer;

    mapping(uint256 => bool) public isClaimed;
    mapping(uint256 => uint256) public numClaimed;

    event UpdateSigner(address signer);

    event EventClaim(
        uint256 nftID,
        uint256 _pid,
        uint256 _dummyId,
        uint256 _level,
        address _nft,
        address _mintTo,
        bool _canTranster
    );

    constructor() EIP712("SecondLive", "1.0.0") {}
    
    function initialize(address _owner, address _signer) external {

        require(!initialized, "initialize: Already initialized!");
        eip712Initialize("SecondLive", "1.0.0");
        _transferOwnership(_owner);
        signer = _signer;
        initialized = true;
    }
    function claimHash(
        uint256 _pid,
        address _nft,
        uint256 _dummyId,
        uint256 _level,
        address _to,
        address _royaltyReceiver,
        uint96 _royaltyFeeNumerator, // div.(10000)
        bool _canTranster
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "Claim(uint256 pid,address claimNFT,uint256 dummyId,uint256 level,address mintTo,address royaltyReceiver,uint96 royaltyFeeNumerator,bool canTranster)"
                        ),
                        _pid,
                        _nft,
                        _dummyId,
                        _level,
                        _to,
                        _royaltyReceiver,
                        _royaltyFeeNumerator,
                        _canTranster
                    )
                )
            );
    }

    function verifySignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        return ECDSA.recover(hash, signature) == signer;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
        emit UpdateSigner(_signer);
    }

    function claim(
        uint256 _pid,
        address _nft,
        uint256 _dummyId,
        uint256 _level,
        address _mintTo,
        address _royaltyReceiver,
        uint96 _royaltyFeeNumerator, // div.(10000)
        bool _canTranster,
        bytes calldata _signature
    ) external nonReentrant returns (uint256) {
        require(!isClaimed[_dummyId], "Already Claimed!");

        require(
            verifySignature(
                claimHash(
                    _pid,
                    _nft,
                    _dummyId,
                    _level,
                    _mintTo,
                    _royaltyReceiver,
                    _royaltyFeeNumerator,
                    _canTranster
                ),
                _signature
            ),
            "Invalid signature"
        );
        isClaimed[_dummyId] = true;
        ISecondLiveMedal.Pinfo memory pinfo = ISecondLiveMedal.Pinfo(
            _pid,
            _level,
            _mintTo,
            _canTranster
        );
        uint256 nftID_ = ISecondLiveMedal(_nft).mint(_mintTo, pinfo);
        if (_royaltyFeeNumerator > 0) {
            ISecondLiveMedal(_nft).setTokenRoyalty(
                nftID_,
                _royaltyReceiver,
                _royaltyFeeNumerator
            );
        }

        numClaimed[_pid]++;

        address nft_ = _nft;
        emit EventClaim(
            nftID_,
            _pid,
            _dummyId,
            _level,
            nft_,
            _mintTo,
            _canTranster
        );

        return nftID_;
    }
}

