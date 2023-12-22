pragma solidity ^0.8.0;

import {ERC20} from "./ERC20.sol";
import {MerkleProof} from "./MerkleProof.sol";
import {Ownable} from "./Ownable.sol";

contract DeadCutiesAccessToken is ERC20("DeadCutiesAccessToken", "DeadCutiesAccessToken"), Ownable {

    /*  
    ================================================================
                            State 
    ================================================================ 
    */

    bytes32 merkleRoot;

    address theDeadCuties;

    mapping(address => bool) hasClaimed;

    /*  
    ================================================================
                        Public Functions
    ================================================================ 
    */

    /**
    * @dev If you are an airdrop reciever this will send you 1 DeadCuties Access Token
    * @param proof To get your proof go to https://discord.gg/3QVfkfYpB9 and ask our bot to provide it for you
    */
    function mint(bytes32[] calldata proof) external verifyProof(proof) checkIfSenderHasClaimedAlready() {
        _mint(msg.sender, 1);
    }

    /*  
    ================================================================
                    Public view Functions
    ================================================================ 
    */

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function _hasClaimed(address account) public view returns (bool) {
        return hasClaimed[account];
    }

    /*  
    ================================================================
                            Modifers 
    ================================================================ 
    */

    modifier verifyProof(bytes32[] calldata proof) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(proof, merkleRoot, leaf) == true, "DeadCutiesAccessToken: proof/leaf invalid");
        _;
    }

    modifier checkIfSenderHasClaimedAlready() {
        require(hasClaimed[msg.sender] == false, "DeadCutiesAccessToken: Already claimed");
        hasClaimed[msg.sender] = true;
        _;
    }

    /*  
    ================================================================
                            Internal Functions 
    ================================================================ 
    */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal override {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max && spender != theDeadCuties) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /*  
    ================================================================
                            Owner Functions 
    ================================================================ 
    */

    function setRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setDeadCutiesAddress(address _theDeadCuties) external onlyOwner {
        theDeadCuties = _theDeadCuties;
    }

    function ownerMintForGiveaways(uint amount) external onlyOwner {
        _mint(msg.sender, amount);
    }

}

