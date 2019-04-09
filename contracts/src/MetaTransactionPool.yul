object "SimpleStore" {
  code {
    // constructor code

    datacopy(0, dataoffset("Runtime"), datasize("Runtime"))  // runtime code
    return(0, datasize("Runtime"))
  }
  object "Runtime" {
    code {
      calldatacopy(1000, 0, 384) // copy calldata to memory

      switch and(shr(224, mload(1000)), 0xffffffff) // 4 byte method signature

      case 0x6057361d { // transfer()
          mstore(872, 0xab469e7fbcec1c8479ef92e0679557fec6555752321c3649c6b102845f9dddaf) // Transfer Hash

          if eq(mload(1288), 0) { // if sig2 v does not exist
              mstore(904, and(shr(96, mload(1012)), 0xffffffffffffffffffffffffffffffffffffffff)) // recipient address
          }

          if gt(mload(1288), 0) { // if sig2 v exists
            mstore(3000, mload(1256)) // store sig1 s at 3k
            mstore(1256, mload(1000))
            if iszero(call(3000, 1, 0, 1256, 128, 904, 32)) { revert(0, 0) } // get recipient address
            mstore(1256, mload(3000)) // put back sig1 s at 1256
            mstore(968, 0x0000000000000000000000000000000000000000000000000000000000000001)
          }

          mstore(936, and(mload(1001), 0xffffffffffffffffffff))

          if lt(byte(0, mload(1000)), 2) {
            mstore(1000, 0x0000000000000000000000000000000000000000000000000000000000000001)
          }

          if lt(timestamp(), mload(1160)) { revert(0, 0) }

          mstore(0, 0x1901)
          mstore(2, sload(0))
          mstore(34, keccak256(872, 352)) // Transfer Sub Hash
          mstore(4004, keccak256(0, 66)) // release hash

          if iszero(call(3000, 1, 0, 1160, 128, 4036, 32)) { revert(0, 0) } // get recipient address

          // 4000) bytes4(releaseHashSig) + bytes32(releaseHash) + bytes32(from)

          mstore(4000, 0x6057361d) // releaseHashes sig
          mstore(4000, keccak256(4000, 68)) // releaseHash[from][releaseHash]
          if gt(sload(mload(4000)), 0) { revert(0, 0) } // releaseHash[from][releaseHash] == false

          sstore(mload(4000), 1) // set release hash as used


      }



      case 0x6d4ce63c {
      }
    }
  }
}


/*
    1000) bytes32 destination, // 0x00 or 01 or 02 ... 0000 ... address

    1032) address token,
    1064) uint256 amount,
    1096) address payable feeRecipient,
    1128) uint256 fee,
    1160) uint256 expiry,

    1192) sig1 v
    1224) sig1 r
    1256) sig1 s

    1288) sig2 v
    1320) sig2 r
    1352) sig2 s
*/

/*
    872) SIGNEDTRANSFER_TYPEHASH,
    904) (signatures.length == 6)
          ? ecrecover(destination, uint8(signatures[3][31]), signatures[4], signatures[5])
          : recipient,
    936) bytes11(destination << 8),
    968) signatures.length == 6 ? true : false,
    1000) uint8(kind) <= 1 ? true : false,
    1032) address token,
    1064) uint256 amount,
    1096) address payable feeRecipient,
    1128) uint256 fee,
    1160) uint256 expiry,
*/
