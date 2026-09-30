#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/resource.h>

#include "shamir.h"
#include "bc-bytewords.h"
#include <bc-crypto-base/bc-crypto-base.h>

#define SECRET_LEN 32
#define SET_ID_LEN 8
#define RECORD_LEN (2 + 1 + SET_ID_LEN + 1 + 1 + 1 + SECRET_LEN)
#define MAX_LINE 1024

static void fail(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    exit(1);
}

static void harden_process(void) {
    struct rlimit limit = {0, 0};
    if (setrlimit(RLIMIT_CORE, &limit) != 0) fail("Unable to disable core dumps.");
}

static void secure_random(uint8_t *out, size_t len, void *ctx) {
    (void)ctx;
    while (len > 0) {
        ssize_t n = getrandom(out, len, 0);
        if (n < 0) {
            if (errno == EINTR) continue;
            fail("getrandom failed.");
        }
        if (n == 0) fail("getrandom returned no data.");
        out += (size_t)n;
        len -= (size_t)n;
    }
}

static void read_exact(uint8_t *out, size_t len) {
    size_t done = 0;
    while (done < len) {
        size_t n = fread(out + done, 1, len - done, stdin);
        if (n == 0) fail("Short secret input.");
        done += n;
    }
    if (fgetc(stdin) != EOF) fail("Unexpected extra secret input.");
}

static void write_exact(const uint8_t *buf, size_t len) {
    if (fwrite(buf, 1, len, stdout) != len || fflush(stdout) != 0) fail("Output failed.");
}

static int policy_ok(uint8_t threshold, uint8_t count) {
    return (threshold == 2 && count == 3) ||
           (threshold == 3 && count == 5) ||
           (threshold == 3 && count == 7);
}

static int parse_u8(const char *s, uint8_t *out) {
    char *end = NULL;
    errno = 0;
    long value = strtol(s, &end, 10);
    if (errno || !end || *end || value < 0 || value > 255) return 0;
    *out = (uint8_t)value;
    return 1;
}

static void trim_line(char *line) {
    size_t n = strlen(line);
    while (n && (line[n - 1] == '\n' || line[n - 1] == '\r' || line[n - 1] == ' ' || line[n - 1] == '\t')) {
        line[--n] = '\0';
    }
    char *p = line;
    while (*p == ' ' || *p == '\t') p++;
    if (p != line) memmove(line, p, strlen(p) + 1);
}

static int decode_record(const char *line, uint8_t record[RECORD_LEN]) {
    uint8_t *decoded = NULL;
    size_t decoded_len = 0;
    if (!bytewords_decode(bw_standard, line, &decoded, &decoded_len)) return 0;
    int ok = decoded_len == RECORD_LEN &&
             decoded[0] == 'S' && decoded[1] == 'S' && decoded[2] == 1 &&
             policy_ok(decoded[11], decoded[12]) &&
             decoded[13] < decoded[12];
    if (ok) memcpy(record, decoded, RECORD_LEN);
    memzero(decoded, decoded_len);
    free(decoded);
    return ok;
}

static void print_metadata(const uint8_t record[RECORD_LEN]) {
    for (size_t i = 0; i < SET_ID_LEN; ++i) printf("%02x", record[3 + i]);
    printf(" %u %u %u\n", record[11], record[12], (unsigned)record[13] + 1U);
}

static void command_split(uint8_t threshold, uint8_t count) {
    if (!policy_ok(threshold, count)) fail("Unsupported share policy.");
    uint8_t secret[SECRET_LEN];
    uint8_t shares[SHAMIR_MAX_SHARE_COUNT * SECRET_LEN];
    uint8_t set_id[SET_ID_LEN];
    uint8_t record[RECORD_LEN];

    read_exact(secret, sizeof(secret));
    secure_random(set_id, sizeof(set_id), NULL);
    int32_t made = split_secret(threshold, count, secret, SECRET_LEN, shares, NULL, secure_random);
    if (made != count) fail("Shamir split failed.");

    for (uint8_t i = 0; i < count; ++i) {
        record[0] = 'S'; record[1] = 'S'; record[2] = 1;
        memcpy(record + 3, set_id, SET_ID_LEN);
        record[11] = threshold;
        record[12] = count;
        record[13] = i;
        memcpy(record + 14, shares + ((size_t)i * SECRET_LEN), SECRET_LEN);
        char *encoded = bytewords_encode(bw_standard, record, sizeof(record));
        if (!encoded) fail("Bytewords encode failed.");
        puts(encoded);
        memzero(encoded, strlen(encoded));
        free(encoded);
    }
    fflush(stdout);
    memzero(secret, sizeof(secret));
    memzero(shares, sizeof(shares));
    memzero(set_id, sizeof(set_id));
    memzero(record, sizeof(record));
}

static void command_validate(void) {
    char line[MAX_LINE];
    uint8_t record[RECORD_LEN];
    if (!fgets(line, sizeof(line), stdin)) fail("Missing share.");
    trim_line(line);
    if (!decode_record(line, record)) fail("Invalid share or checksum.");
    print_metadata(record);
    memzero(record, sizeof(record));
    memzero(line, sizeof(line));
}

static void command_recover(void) {
    char line[MAX_LINE];
    uint8_t records[SHAMIR_MAX_SHARE_COUNT][RECORD_LEN];
    const uint8_t *share_ptrs[SHAMIR_MAX_SHARE_COUNT];
    uint8_t x[SHAMIR_MAX_SHARE_COUNT];
    uint8_t secret[SECRET_LEN];
    uint8_t supplied = 0;
    uint8_t threshold = 0, count = 0;
    uint8_t set_id[SET_ID_LEN] = {0};
    uint16_t seen = 0;

    while (fgets(line, sizeof(line), stdin)) {
        trim_line(line);
        if (line[0] == '\0') continue;
        if (supplied >= SHAMIR_MAX_SHARE_COUNT) fail("Too many shares.");
        if (!decode_record(line, records[supplied])) fail("Invalid share or checksum.");
        uint8_t *r = records[supplied];
        if (supplied == 0) {
            memcpy(set_id, r + 3, SET_ID_LEN);
            threshold = r[11];
            count = r[12];
        } else if (memcmp(set_id, r + 3, SET_ID_LEN) != 0 || threshold != r[11] || count != r[12]) {
            fail("Shares do not belong to the same set.");
        }
        uint8_t index = r[13];
        if (seen & (uint16_t)(1U << index)) fail("Duplicate share.");
        seen |= (uint16_t)(1U << index);
        x[supplied] = index;
        share_ptrs[supplied] = r + 14;
        supplied++;
    }
    if (!policy_ok(threshold, count) || supplied != threshold) fail("Provide exactly the threshold number of shares.");
    if (recover_secret(threshold, x, share_ptrs, SECRET_LEN, secret) != SECRET_LEN) fail("Shamir recovery failed.");
    write_exact(secret, sizeof(secret));
    memzero(secret, sizeof(secret));
    memzero(records, sizeof(records));
    memzero(share_ptrs, sizeof(share_ptrs));
    memzero(x, sizeof(x));
    memzero(set_id, sizeof(set_id));
    memzero(line, sizeof(line));
}

static void selftest(void) {
    const uint8_t sample[] = {'H','e','l','l','o','\n'};
    const char *expected = "fund inch jazz jazz jowl back each mint epic calm";
    char *encoded = bytewords_encode(bw_standard, sample, sizeof(sample));
    if (!encoded || strcmp(encoded, expected) != 0) fail("Bytewords vector failed.");
    uint8_t *decoded = NULL;
    size_t decoded_len = 0;
    if (!bytewords_decode(bw_standard, encoded, &decoded, &decoded_len) ||
        decoded_len != sizeof(sample) || memcmp(decoded, sample, sizeof(sample)) != 0) fail("Bytewords decode failed.");
    memzero(encoded, strlen(encoded)); free(encoded);
    memzero(decoded, decoded_len); free(decoded);

    uint8_t secret[SECRET_LEN], shares[5 * SECRET_LEN], recovered[SECRET_LEN];
    const uint8_t *ptrs[3] = {shares, shares + (2 * SECRET_LEN), shares + (4 * SECRET_LEN)};
    const uint8_t indexes[3] = {0, 2, 4};
    for (uint8_t i = 0; i < SECRET_LEN; ++i) secret[i] = i;
    if (split_secret(3, 5, secret, SECRET_LEN, shares, NULL, secure_random) != 5) fail("Shamir selftest split failed.");
    if (recover_secret(3, indexes, ptrs, SECRET_LEN, recovered) != SECRET_LEN ||
        memcmp(secret, recovered, SECRET_LEN) != 0) fail("Shamir selftest recover failed.");
    memzero(secret, sizeof(secret)); memzero(shares, sizeof(shares)); memzero(recovered, sizeof(recovered));
    puts("OK");
}

int main(int argc, char **argv) {
    harden_process();
    if (argc == 2 && strcmp(argv[1], "selftest") == 0) {
        selftest();
        return 0;
    }
    if (argc == 4 && strcmp(argv[1], "split") == 0) {
        uint8_t threshold, count;
        if (!parse_u8(argv[2], &threshold) || !parse_u8(argv[3], &count)) fail("Invalid policy.");
        command_split(threshold, count);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "validate") == 0) {
        command_validate();
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "recover") == 0) {
        command_recover();
        return 0;
    }
    fail("Usage: shamir-helper selftest | split T N | validate | recover");
    return 1;
}
