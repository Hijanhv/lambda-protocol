// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ICoreWriter
/// @notice Minimal interface to Hyperliquid's CoreWriter system precompile on HyperEVM.
/// @dev    The precompile lives at a fixed address and exposes a single entry point that
///         forwards a raw, version-framed action to Hyperliquid L1 (perps/spot). We keep
///         only what Lambda needs; the action bytes are built by {CoreWriterLib}.
///
///         This is a *live* system contract (README §"the rails Lambda builds on are
///         already live"), not a mock — the address below is the canonical one.
interface ICoreWriter {
    /// @notice Submit a single raw L1 action.
    /// @param data Version byte (0x01) + 3-byte action id + ABI-encoded action arguments.
    function sendRawAction(bytes calldata data) external;
}

// Canonical address of the CoreWriter precompile on HyperEVM (README §③).
address constant CORE_WRITER = 0x3333333333333333333333333333333333333333;
