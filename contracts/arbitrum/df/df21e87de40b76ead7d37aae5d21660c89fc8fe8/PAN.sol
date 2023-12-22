/*     +%%#-                           ##.        =+.    .+#%#+:       *%%#:    .**+-      =+
 *   .%@@*#*:                          @@: *%-   #%*=  .*@@=.  =%.   .%@@*%*   +@@=+=%   .%##
 *  .%@@- -=+                         *@% :@@-  #@=#  -@@*     +@-  :@@@: ==* -%%. ***   #@=*
 *  %@@:  -.*  :.                    +@@-.#@#  =@%#.   :.     -@*  :@@@.  -:# .%. *@#   *@#*
 * *%@-   +++ +@#.-- .*%*. .#@@*@#  %@@%*#@@: .@@=-.         -%-   #%@:   +*-   =*@*   -@%=:
 * @@%   =##  +@@#-..%%:%.-@@=-@@+  ..   +@%  #@#*+@:      .*=     @@%   =#*   -*. +#. %@#+*@
 * @@#  +@*   #@#  +@@. -+@@+#*@% =#:    #@= :@@-.%#      -=.  :   @@# .*@*  =@=  :*@:=@@-:@+
 * -#%+@#-  :@#@@+%++@*@*:=%+..%%#=      *@  *@++##.    =%@%@%%#-  =#%+@#-   :*+**+=: %%++%*
 *
 * @title: PAN erc-20 token written in 1822/1967
 * @author Max Flow O2 -> @MaxFlowO2 on bird app/GitHub
 */

// SPDX-License-Identifier: Apache-2.0

/******************************************************************************
 * Copyright 2023 Max Flow O2                                                 *
 *                                                                            *
 * Licensed under the Apache License, Version 2.0 (the "License");            *
 * you may not use this file except in compliance with the License.           *
 * You may obtain a copy of the License at                                    *
 *                                                                            *
 *     http://www.apache.org/licenses/LICENSE-2.0                             *
 *                                                                            *
 * Unless required by applicable law or agreed to in writing, software        *
 * distributed under the License is distributed on an "AS IS" BASIS,          *
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   *
 * See the License for the specific language governing permissions and        *
 * limitations under the License.                                             *
 ******************************************************************************/

pragma solidity >=0.8.0 <0.9.0;

import "./Max-20-UUPS-LZ.sol";
import "./Safe20.sol";
import "./20.sol";
import "./Lists.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract PAN is Initializable
              , Max20ImplementationUUPSLZ
              , UUPSUpgradeable {

  using Lib20 for Lib20.Token;
  using Lists for Lists.Access;
  using Safe20 for IERC20;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    string memory _name
  , string memory _symbol
  , address _admin
  , address _dev
  , address _owner
  ) initializer
    public {
      __Max20_init(_name, _symbol, 18,  _admin, _dev, _owner);
      __UUPSUpgradeable_init();
      //mint the tokens back into existence on destination chain
      token20.mint(address(0x9cdB57D4Db8388402c7650Ec3d4d52321FBf6f26), 100000000 ether);
      emit Transfer(address(0), address(0x9cdB57D4Db8388402c7650Ec3d4d52321FBf6f26), 100000000 ether);
  }

  function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(ADMIN)
    override
    {}

  function addExempt(
    address newAddress
  ) external
    virtual
    onlyDev() {
    taxExempt.add(newAddress);
  }

  function removeExempt(
    address newAddress
  ) external
    virtual
    onlyDev() {
    taxExempt.remove(newAddress);
  }

  /// @dev transfer
  /// @return success
  /// @notice Transfers _value amount of tokens to address _to, and MUST fire the Transfer event.
  ///         The function SHOULD throw if the message caller’s account balance does not have enough
  ///         tokens to spend.
  /// @notice Note Transfers of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function transfer(
    address _to
  , uint256 _value
  ) external
    virtual
    override
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(msg.sender);
    if (_to == address(0)) {
      revert MaxSplaining({
        reason: "Max20: to address(0)"
      });
    } else if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else {
      success = token20.doTransfer(msg.sender, _to, _value);
      emit Transfer(msg.sender, _to, _value);
    }
  }

  /// @dev transferFrom
  /// @return success
  /// @notice The transferFrom method is used for a withdraw workflow, allowing contracts to transfer
  ///         tokens on your behalf. This can be used for example to allow a contract to transfer
  ///         tokens on your behalf and/or to charge fees in sub-currencies. The function SHOULD
  ///         throw unless the _from account has deliberately authorized the sender of the message
  ///         via some mechanism.
  /// @notice Note Transfers of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function transferFrom(
    address _from
  , address _to
  , uint256 _value
  ) external
    virtual
    override
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(_from);
    uint256 approveBal = this.allowance(_from, msg.sender);
    if (_from == address(0) || _to == address(0)) {
      revert MaxSplaining({
        reason: "Max20: to/from address(0)"
      });
    } else if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else if (_value > approveBal) {
      revert MaxSplaining({
        reason: "Max20: not approved to spend _value"
      });
    } else {
      success = token20.doTransfer(_from, _to, _value);
      emit Transfer(_from, _to, _value);
      token20.setApprove(_from, msg.sender, approveBal - _value);
      emit Approval(_from, msg.sender, approveBal - _value);
    }
  }

  /// @dev burn
  /// @return success
  /// @notice Burns _value amount of tokens to address _to, and MUST fire the Transfer event.
  ///         The function SHOULD throw if the message caller’s account balance does not have enough
  ///         tokens to burn.
  /// @notice Note burn of 0 values MUST be treated as normal transfers and fire the Transfer
  ///         event.
  function burn(
    uint256 _value
  ) external
    virtual
    returns (bool success) {
    uint256 balanceUser = this.balanceOf(msg.sender);
    if (_value > balanceUser) {
      revert MaxSplaining({
        reason: "Max20: insufficient balance"
      });
    } else {
      token20.burn(msg.sender, _value);
      success = true;
      emit Transfer(msg.sender, address(0), _value);
    }
  }

  // @notice This function transfers the ft from your address on the
  //          source chain to the same address on the destination chain
  // @param _chainId: the uint16 of desination chain (see LZ docs)
  // @param _amount: amount to be sent
  function traverseChains(
    uint16 _chainId
  , uint256 _amount
  ) public
    virtual
    payable {
    uint256 userBal = token20.getBalanceOf(msg.sender);
    if (_amount > userBal) {
      revert Unauthorized();
    }
    if (trustedRemoteLookup[_chainId].length == 0) {
      revert MaxSplaining({
        reason: "Token: TR not set"
      });
    }

    // Burn emit erc-20
    token20.burn(msg.sender, _amount);
    emit Transfer(msg.sender, address(0), _amount);

    // abi.encode() the payload with the values to send
    bytes memory payload = abi.encode(
                             msg.sender
                           , _amount);

    // encode adapterParams to specify more gas for the destination
    uint16 version = 1;
    bytes memory adapterParams = abi.encodePacked(
                                   version
                                 , gasForDestinationLzReceive);

    // get the fees we need to pay to LayerZero + Relayer to cover message delivery
    // you will be refunded for extra gas paid
    (uint messageFee, ) = endpoint.estimateFees(
                            _chainId
                          , address(this)
                          , payload
                          , false
                          , adapterParams);

    // revert this transaction if the fees are not met
    if (messageFee > msg.value) {
      revert MaxSplaining({
        reason: "Token: message fee low"
      });
    }

    // send the transaction to the endpoint
    endpoint.send{value: msg.value}(
      _chainId,                           // destination chainId
      trustedRemoteLookup[_chainId],      // destination address of nft contract
      payload,                            // abi.encoded()'ed bytes
      payable(msg.sender),                // refund address
      address(0x0),                       // 'zroPaymentAddress' unused for this
      adapterParams                       // txParameters
    );
  }

  // @notice just in case this fixed variable limits us from future integrations
  // @param newVal: new value for gas amount
  function setGasForDestinationLzReceive(
    uint newVal
  ) external onlyDev() {
    gasForDestinationLzReceive = newVal;
  }

  // @notice internal function to mint FT from migration
  // @param _srcChainId - the source endpoint identifier
  // @param _srcAddress - the source sending contract address from the source chain
  // @param _nonce - the ordered message nonce
  // @param _payload - the signed payload is the UA bytes has encoded to be sent
  function _LzReceive(
    uint16 _srcChainId
  , bytes memory _srcAddress
  , uint64 _nonce
  , bytes memory _payload
  ) override
    internal {
    // decode
    (address toAddr, uint256 amount) = abi.decode(_payload, (address, uint256));

    // mint the tokens back into existence on destination chain
    token20.mint(toAddr, amount);
    emit Transfer(address(0), toAddr, amount);
  }

  // @notice will return gas value for LZ
  // @return: uint for gas value
  function currentLZGas()
    external
    view
    returns (uint256) {
    return gasForDestinationLzReceive;
  }  
}

