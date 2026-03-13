defmodule BtcTxFeed.TxParserTest do
  use ExUnit.Case, async: true

  alias BtcTxFeed.TxParser

  # Fixtures sourced from deps/btc_tx/test/btc_tx_test.gleam and Bitcoin block 1.

  # Legacy V1: 1 input, 33 P2PKH outputs, lock_time 939_066
  @legacy_v1_hex "010000000173ea7c1caa2dc6669848997864cb9f597284760654a98f67f321ae78d89dcd380a0000006a4730440220185e66bef2903df84f7eb68c4eedb17bcf59f416324e1807e41461cad39aee8202200cbe809bfbac0f33ed5a23fc70473ff64462e225b9218b568bf5e13a11832445012103c3a5d7ca9937c6f862e3454d679171e90e7ff6d8147b0725cfae909a1c94a538feffffff2122020000000000001976a9145349473a38385c482b2f6a2b6d5476534b6f394f88ac22020000000000001976a91455677a584a742b5a544a5262516a627a50716b3888ac22020000000000001976a9146e7473336b746356685451555a5177326d55373788acdd3f0000000000001976a914b02562ff4e772f0875fbb4cccbc15ef08c431f3e88ac22020000000000001976a91448324f70644f667a36764e544665474a586d776688ac22020000000000001976a9144744756e56484142754a68586e513d4f424a5c3388ac22020000000000001976a91432362f7b2275726e223a2239346637313165353088ac22020000000000001976a914346238643131633162373835613162393663613088ac22020000000000001976a914383531333039376164663361316631303834313688ac22020000000000001976a9146535656134643733623437646166652f4120736d88ac22020000000000001976a914616c6c206d6573736167652e6a7067222c226e6d88ac22020000000000001976a91465223a2266756e6b20796f75222c22637265223a88ac22020000000000001976a9145b223139434b474c61426a64707045706148537488ac22020000000000001976a91438776e727a5371487838356850643955222c223188ac22020000000000001976a91444764e5039385a664857376d53397634426a375288ac22020000000000001976a9147436477457567844344c625a37222c223136726288ac22020000000000001976a9143979413746595150545570775a4a73575a56373788ac22020000000000001976a91466575555477366477077225d2c226f776e223a7b88ac22020000000000001976a914223139434b474c61426a6470704570614853743888ac22020000000000001976a914776e727a5371487838356850643955223a397d2c88ac22020000000000001976a91422726f79223a7b22314233444c725936344c4e6988ac22020000000000001976a91467775071755356414c64704b484563774a546a4688ac22020000000000001976a9144d59223a352e307d7d232323232323232323232388ac22020000000000001976a914393466373131653530346238643131633162373888ac22020000000000001976a914a968f1d8335db1404e32b6b360952e4bdd7ab20088ac22020000000000001976a91466756e6b2323232323232323232323232323232388ac22020000000000001976a914796f75232323232323232323232323232323232388ac22020000000000001976a9147032666b2323232323232323232323232323232388ac22020000000000001976a914656d62696923232323232323232323232323232388ac22020000000000001976a9146e1c6481b500237b14c7c474ae728e670d3b757588ac22020000000000001976a9144039859aabef04c076fd641744faedb3ee240f1588ac22020000000000001976a91459e4d4073fe0680c02fffb0cfe5ad923bf5c1f6588ac22020000000000001976a9148db967691586d193770e916d8cb9475d4118094988ac3a540e00"

  # SegWit V1: 2 inputs, 2 P2WPKH outputs, lock_time 0
  @segwit_v1_hex "01000000000102abbcae618dc866eff678eb59b617add6995a9b43e18f9156d3683a32554ea0790a00000000ffffffffbc3a57d8b85c9b691169c41d1184a60041eba5a8ac1bfcbf2368b2df286e38b33300000000ffffffff0257cc010000000000160014a6eed0138c8d330892a50ace4b7170899aeccf95304200000000000016001404daa8d90ec7ec9c0a394fc28ae8dd21b1ba568002483045022100d096adfb49bbba07fe723266027739075f968acf256acb986c63e34fffff434b0220156cc75d54f3fcea9c7d0b24ed7c40a7955ce516fa55fa656018bdc0aa8c3c780121027c052450a0b9ee7116b40a2402c2c4772ea4502f6c168d251dc77b0560b6baca02483045022100ada5c1e2de004e68ef9ffb68936b7dd0cff9aaa1d3fb3cb128d8afd3dc9868e10220505adec079e5d5af4bc4a7f4a89dbde8167b18ea00d3c3e460d3e6eadf23bd110121027c052450a0b9ee7116b40a2402c2c4772ea4502f6c168d251dc77b0560b6baca00000000"

  # Legacy V2: 1 input, 1 P2SH output (679 sats), lock_time 0
  @legacy_v2_hex "02000000019945a5a440f2d3712ff095cb1efefada1cc52e139defedb92a313daed49d5678010000006a473044022031b6a6b79c666d5568a9ac7c116cacf277e11521aebc6794e2b415ef8c87c899022001fe272499ea32e6e1f6e45eb656973fbb55252f7acc64e1e1ac70837d5b7d9f0121023dec241e4851d1ec1513a48800552bae7be155c6542629636bcaa672eee971dcffffffff01a70200000000000017a9148ce773d254dc5df886b95848880e0b40f10564328700000000"

  # Block 1 coinbase: 1 input (coinbase marker), 1 P2PK output (50 BTC), lock_time 0
  # txid: 0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098
  @coinbase_hex "01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0704ffff001d0104ffffffff0100f2052a0100000043410496b538e853519c726a2c91e61ec11600ae1390813a627c66fb8be7947be63c52da7589379515d4e0a604f8141781e62294721166bf621e73a82cbf2342c858eeac00000000"

  defp raw(hex), do: Base.decode16!(hex, case: :lower)

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  describe "parse/1 error handling" do
    test "returns error for empty binary" do
      assert {:error, _} = TxParser.parse(<<>>)
    end

    test "returns error for truncated/garbage bytes" do
      assert {:error, _} = TxParser.parse(<<1, 0, 0, 0, 0, 0>>)
    end
  end

  # ---------------------------------------------------------------------------
  # Legacy V1 transaction
  # ---------------------------------------------------------------------------

  describe "parse/1 with a legacy V1 transaction" do
    setup do
      {:ok, details} = TxParser.parse(raw(@legacy_v1_hex))
      %{details: details}
    end

    test "version is 1", %{details: details} do
      assert details.version == 1
    end

    test "is not segwit", %{details: details} do
      refute details.is_segwit
    end

    test "lock_time matches", %{details: details} do
      assert details.lock_time == 939_066
    end

    test "has no coinbase marker", %{details: details} do
      refute details.has_coinbase_marker
    end

    test "input_count is 1", %{details: details} do
      assert details.input_count == 1
      assert length(details.inputs) == 1
    end

    test "input has all expected fields", %{details: details} do
      [input] = details.inputs
      assert byte_size(input.prev_txid_hex) == 64
      assert is_integer(input.prev_vout)
      assert is_integer(input.sequence)
      assert is_binary(input.script_sig_hex)
      assert input.script_sig_length > 0
    end

    test "output_count is 33", %{details: details} do
      assert details.output_count == 33
      assert length(details.outputs) == 33
    end

    test "all outputs are P2PKH", %{details: details} do
      for output <- details.outputs do
        assert output.script_type == :p2_p_k_h
      end
    end

    test "outputs include value_sats and script fields", %{details: details} do
      [output | _] = details.outputs
      assert output.value_sats > 0
      assert is_binary(output.script_pubkey_hex)
      assert output.script_pubkey_length == 25
    end

    test "witnesses list is empty", %{details: details} do
      assert details.witnesses == []
    end

    test "validated txid is a 64-char hex string", %{details: details} do
      assert Map.has_key?(details, :txid)
      assert byte_size(details.txid) == 64
    end

    test "weight and size fields are present", %{details: details} do
      assert details.weight > 0
      assert details.vsize > 0
      assert details.base_size == details.total_size
    end
  end

  # ---------------------------------------------------------------------------
  # SegWit V1 transaction
  # ---------------------------------------------------------------------------

  describe "parse/1 with a SegWit transaction" do
    setup do
      {:ok, details} = TxParser.parse(raw(@segwit_v1_hex))
      %{details: details}
    end

    test "version is 1", %{details: details} do
      assert details.version == 1
    end

    test "is segwit", %{details: details} do
      assert details.is_segwit
    end

    test "lock_time is 0", %{details: details} do
      assert details.lock_time == 0
    end

    test "input_count is 2", %{details: details} do
      assert details.input_count == 2
      assert length(details.inputs) == 2
    end

    test "inputs have empty script sigs (native segwit)", %{details: details} do
      for input <- details.inputs do
        assert input.script_sig_length == 0
        assert input.script_sig_hex == ""
      end
    end

    test "output_count is 2", %{details: details} do
      assert details.output_count == 2
      assert length(details.outputs) == 2
    end

    test "all outputs are P2WPKH", %{details: details} do
      for output <- details.outputs do
        assert output.script_type == :p2_w_p_k_h
      end
    end

    test "witnesses list has one stack per input", %{details: details} do
      assert length(details.witnesses) == 2
    end

    test "each witness stack has indexed items with hex bytes", %{details: details} do
      for stack <- details.witnesses do
        assert length(stack) > 0

        for item <- stack do
          assert Map.has_key?(item, :index)
          assert Map.has_key?(item, :item_hex)
          assert is_binary(item.item_hex)
        end
      end
    end

    test "txid and wtxid differ for segwit tx", %{details: details} do
      assert byte_size(details.txid) == 64
      assert byte_size(details.wtxid) == 64
      assert details.txid != details.wtxid
    end

    test "total_size exceeds base_size due to witness data", %{details: details} do
      assert details.total_size > details.base_size
    end

    test "weight follows BIP 141 formula", %{details: details} do
      expected = details.base_size * 3 + details.total_size
      assert details.weight == expected
    end

    test "vsize is ceil(weight / 4)", %{details: details} do
      assert details.vsize == ceil(details.weight / 4)
    end
  end

  # ---------------------------------------------------------------------------
  # Legacy V2 transaction
  # ---------------------------------------------------------------------------

  describe "parse/1 with a legacy V2 transaction" do
    setup do
      {:ok, details} = TxParser.parse(raw(@legacy_v2_hex))
      %{details: details}
    end

    test "version is 2", %{details: details} do
      assert details.version == 2
    end

    test "is not segwit", %{details: details} do
      refute details.is_segwit
    end

    test "output is P2SH with expected value", %{details: details} do
      [output] = details.outputs
      assert output.script_type == :p2_s_h
      assert output.value_sats == 679
    end

    test "witnesses list is empty", %{details: details} do
      assert details.witnesses == []
    end
  end

  # ---------------------------------------------------------------------------
  # Coinbase transaction (Bitcoin block 1)
  # ---------------------------------------------------------------------------

  describe "parse/1 with a coinbase transaction" do
    setup do
      {:ok, details} = TxParser.parse(raw(@coinbase_hex))
      %{details: details}
    end

    test "detects coinbase marker", %{details: details} do
      assert details.has_coinbase_marker
    end

    test "prev_txid_hex is all zeros", %{details: details} do
      [input] = details.inputs
      assert input.prev_txid_hex == String.duplicate("0", 64)
    end

    test "prev_vout is 0xFFFFFFFF (coinbase sentinel)", %{details: details} do
      [input] = details.inputs
      assert input.prev_vout == 0xFFFFFFFF
    end

    test "output is P2PK with 50 BTC value", %{details: details} do
      [output] = details.outputs
      assert output.script_type == :p2_p_k
      assert output.value_sats == 5_000_000_000
    end

    test "witnesses list is empty", %{details: details} do
      assert details.witnesses == []
    end

    test "txid matches known block 1 coinbase txid", %{details: details} do
      assert details.txid == "0e3e2357e806b6cdb1f70b54c3a3a17b6714ee1f0e68bebb44a74b1efd512098"
    end
  end
end
