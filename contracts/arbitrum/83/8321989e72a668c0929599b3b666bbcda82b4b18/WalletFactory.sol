// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;
import "./WalletSimple.sol";
import "./CloneFactory.sol";

contract WalletFactory is CloneFactory {
  address public implementationAddress;

  mapping (address => bool) public alreadySigner;

  event WalletCreated(address newWalletAddress, address creator, address[] allowedSigners);
  event AddedSigner(address indexed wallet, address signer);
  event RemovedSigner(address indexed wallet, address signer);

  constructor(address _implementationAddress) {
    implementationAddress = _implementationAddress;
  }

  function createWallet(address[] calldata allowedSigners, bytes32 salt)
    public
  {
    bool senderIsSigner = false;

    for(uint256 i = 0; i < allowedSigners.length; i++) {
      require(!alreadySigner[allowedSigners[i]], 'WalletFactory: address already signer');
      alreadySigner[allowedSigners[i]] = true;
      if (allowedSigners[i] == msg.sender) {
        senderIsSigner = true;
      }
    }

    require(senderIsSigner, 'WalletFactory: msg.sender must be one of the signers');

    // include the signers in the salt so any contract deployed to a given address must have the same signers
    bytes32 finalSalt = keccak256(abi.encodePacked(allowedSigners, salt));

    address payable clone = createClone(implementationAddress, finalSalt);
    WalletSimple(clone).init(address(this), allowedSigners);
    emit WalletCreated(clone, msg.sender, allowedSigners);
  }

  function createWalletAndSendEth(address[] calldata allowedSigners, bytes32 salt, address[] calldata fundees, uint256[] calldata amounts)
    public payable
  {
    require(fundees.length == amounts.length, 'WalletFactory: fundees and amounts arrays must have the same length');

    for (uint256 i = 0; i < fundees.length; i++) {
      payable(fundees[i]).transfer(amounts[i]);
    }
    createWallet(allowedSigners, salt);
  }

  function addSignerToWallet(address payable wallet, address newSigner)
    public
  {
    require(!alreadySigner[newSigner], 'WalletFactory: address already signer');
    alreadySigner[newSigner] = true;
    WalletSimple(wallet).addSigner(msg.sender, newSigner);
    emit AddedSigner(wallet, newSigner);
  }


  function addSignerToWalletAndFund(address payable wallet, address payable newSigner, uint256 amount)
    public payable
  {
    require(!alreadySigner[newSigner], 'WalletFactory: address already signer');
    alreadySigner[newSigner] = true;
    newSigner.transfer(amount);
    WalletSimple(wallet).addSigner(msg.sender, newSigner);
    emit AddedSigner(wallet, newSigner);
  }

  function removeSignerFromWallet(address payable wallet, address signerToRemove)
    public
  {
    alreadySigner[signerToRemove] = false;
    WalletSimple(wallet).removeSigner(msg.sender, signerToRemove);
    emit RemovedSigner(wallet, signerToRemove);
  }
}

