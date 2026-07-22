using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace CodexQuotaBall
{
    internal sealed class CodexAuthFingerprint
    {
        private readonly byte[] value;

        private CodexAuthFingerprint(byte[] value)
        {
            this.value = value;
        }

        public static bool TryCapture(string authFilePath, out CodexAuthFingerprint fingerprint)
        {
            fingerprint = null;
            if (String.IsNullOrWhiteSpace(authFilePath))
            {
                return false;
            }

            try
            {
                if (!File.Exists(authFilePath))
                {
                    fingerprint = new CodexAuthFingerprint(HashText("missing"));
                    return true;
                }

                string json;
                using (FileStream stream = new FileStream(
                    authFilePath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete))
                using (StreamReader reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    json = reader.ReadToEnd();
                }

                IDictionary<string, object> root = QuotaJsonParser.ParseObject(json);
                if (root == null)
                {
                    // Codex may be replacing auth.json. Ignore an incomplete write and
                    // keep the previous stable identity until a valid file is readable.
                    return false;
                }

                string authMode = QuotaJsonParser.AsString(
                    QuotaJsonParser.GetAny(root, "auth_mode", "authMode")) ?? String.Empty;
                IDictionary<string, object> tokens = QuotaJsonParser.AsDictionary(
                    QuotaJsonParser.GetAny(root, "tokens"));
                string accountId = QuotaJsonParser.AsString(
                    QuotaJsonParser.GetAny(tokens, "account_id", "accountId"));

                string identity;
                if (!String.IsNullOrWhiteSpace(accountId))
                {
                    // Track the account, not rotating access/refresh tokens. The hash is
                    // retained only in memory and is never written to diagnostics.
                    identity = "account\0" + authMode + "\0" + accountId;
                }
                else
                {
                    string credential = QuotaJsonParser.AsString(
                        QuotaJsonParser.GetAny(
                            root,
                            "OPENAI_API_KEY",
                            "personal_access_token",
                            "bedrock_api_key"));
                    identity = !String.IsNullOrWhiteSpace(credential)
                        ? "credential\0" + authMode + "\0" + credential
                        : "auth-file\0" + json;
                }

                fingerprint = new CodexAuthFingerprint(HashText(identity));
                return true;
            }
            catch (IOException)
            {
                return false;
            }
            catch (UnauthorizedAccessException)
            {
                return false;
            }
        }

        public bool Matches(CodexAuthFingerprint other)
        {
            if (other == null || value == null || other.value == null || value.Length != other.value.Length)
            {
                return false;
            }

            bool matches = true;
            for (int index = 0; index < value.Length; index++)
            {
                matches = matches && value[index] == other.value[index];
            }
            return matches;
        }

        private static byte[] HashText(string text)
        {
            using (SHA256 algorithm = SHA256.Create())
            {
                return algorithm.ComputeHash(Encoding.UTF8.GetBytes(text ?? String.Empty));
            }
        }
    }

    public sealed class CodexAuthStateTracker
    {
        private readonly string authFilePath;
        private CodexAuthFingerprint current;
        private CodexAuthFingerprint pending;

        public CodexAuthStateTracker()
            : this(Path.Combine(SessionQuotaReader.FindCodexHome(), "auth.json"))
        {
        }

        internal CodexAuthStateTracker(string authFilePath)
        {
            this.authFilePath = authFilePath;
            CodexAuthFingerprint.TryCapture(authFilePath, out current);
        }

        public bool PollForStableChange()
        {
            CodexAuthFingerprint observed;
            if (!CodexAuthFingerprint.TryCapture(authFilePath, out observed))
            {
                return false;
            }

            if (current == null)
            {
                current = observed;
                pending = null;
                return false;
            }

            if (current.Matches(observed))
            {
                pending = null;
                return false;
            }

            if (pending != null && pending.Matches(observed))
            {
                current = observed;
                pending = null;
                return true;
            }

            pending = observed;
            return false;
        }
    }

    public static class AccountSwitchQuotaPolicy
    {
        public static bool CanUseRpcGeneration(int generation, int minimumGeneration)
        {
            return generation >= minimumGeneration;
        }

        public static bool CanUseLocalSnapshot(
            QuotaSnapshot snapshot,
            DateTimeOffset? capturedNotBefore)
        {
            if (snapshot == null || !snapshot.HasQuotaData)
            {
                return false;
            }
            return !capturedNotBefore.HasValue
                || snapshot.CapturedAt >= capturedNotBefore.Value;
        }
    }
}
