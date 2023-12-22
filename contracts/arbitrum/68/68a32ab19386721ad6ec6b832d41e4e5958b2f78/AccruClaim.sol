//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IERC20.sol";
import "./ECDSAUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract AccruClaim is Initializable, OwnableUpgradeable {
    using ECDSAUpgradeable for bytes32;
    IERC20 public saleToken;
    bool public paused;

    address public signer;
    mapping(address => uint256) public nonce;

    event TokensClaimed(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract and sets key parameters
     * @param _saleToken address of claim token
     * @param _signer signer to validate signature
     */
    function initialize(
        address _saleToken,
        address _signer
    ) external initializer {
        __Ownable_init_unchained();
        saleToken = IERC20(_saleToken);
        signer = _signer;
    }

    /**
     * @notice Sets the pause status
     * @param _status bool
     */
    function setPause(bool _status) external onlyOwner {
        paused = _status;
    }

    /**
     * @dev To claim tokens after claiming starts
     * @param amount No of amount to claim
     * @param sig signature of claimer
     */
    function claim(uint256 amount, bytes calldata sig) external returns (bool) {
        require(!paused, "Contract Paused");
        require(amount > 0, "Nothing to claim");
        require(
            saleToken.balanceOf(address(this)) >= amount,
            "Insufficient tokens"
        );

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(
                    abi.encodePacked(_msgSender(), amount, nonce[_msgSender()])
                )
            )
        );
        address sigRecover = ECDSAUpgradeable.recover(messageHash, sig);

        require(sigRecover == signer, "Invalid Signer");
        nonce[_msgSender()]++;

        bool success = saleToken.transfer(_msgSender(), amount);
        require(success, "Token transfer failed");
        emit TokensClaimed(_msgSender(), amount);
        return true;
    }

    /**
     * @dev To change signer wallet address
     * @param _signer address
     */
    function setSignerWallet(address _signer) external onlyOwner {
        signer = _signer;
    }
}

