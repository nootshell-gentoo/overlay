#!/usr/bin/env bash




if [ $# -lt 2 ]; then
	cat <<-EOF >&2
	Usage: $0 <new-tmp> FILE [FILE...]
	EOF
	exit 0;
fi


declare OLD_TEMP='/tmp';
declare NEW_TEMP="${1}"; shift;




fetch_file_size() {
	local VAR="${1}"; shift;
	local FILE="${1}"; shift;

	export "${VAR}"="$(stat -c%s "${FILE}")";
}


offset() {
	local VAR="${1}"; shift;
	local SIZE="${1}"; shift;
	local INDEX="${1}"; shift;

	export "${VAR}"=$((SIZE - (4 * (INDEX + 1))));
}


read_dword() {
	local VAR="${1}"; shift;
	local FILE="${1}"; shift;
	local TAIL_INDEX="${1}"; shift;

	local SIZE;
	fetch_file_size SIZE "${FILE}";

	local OFFSET;
	offset OFFSET $((SIZE)) $((TAIL_INDEX));

	export "${VAR}"="$(od -An -t u4 -N 4 -j $((OFFSET)) "${FILE}" | tr -d ' ')";
}


write_dword() {
	local DWORD="${1}"; shift;
	local FILE="${1}"; shift;

	local SIZE;
	fetch_file_size SIZE "${FILE}";
	
	local OFFSET;
	local DWORD_BIN="";
	for TAIL_INDEX in "${@}"; do
		offset OFFSET $((SIZE)) $((TAIL_INDEX));
		printf '0x%02X 0x%02X 0x%02X 0x%02X' $((DWORD & 0xFF)) $(((DWORD >> 8) & 0xFF)) $(((DWORD >> 16) & 0xFF)) $(((DWORD >> 24) & 0xFF)) | xxd -r | dd of="${FILE}" seek=$((OFFSET)) bs=1 count=4 conv=notrunc,fsync >/dev/null 2>&1
		echo "Wrote $((DWORD)) to $((OFFSET))";
	done
}




patch_bundle() {
	local OLD_TEMP="${1}"; shift;
	local NEW_TEMP="${1}"; shift;
	local FILE="${1}"; shift;

	if ! grep -q 'mktemp -d [^$]*/vmis.X' "${FILE}"; then
		echo 'File (probably) not a VMware bundle:' "${FILE}" >&2;
		return 1;
	fi

	local N_PATCHES="$(grep --binary-files=text "\(mktemp \(-d \)\?\)${OLD_TEMP}" "${FILE}" | wc -l)";
	if ((!N_PATCHES)); then
		echo 'No matching lines, not doing anything:' "${FILE}" >&2;
		return 1;
	fi

	# Calculate offset delta 
	local TMPLEN_OLD=${#OLD_TEMP};
	local TMPLEN_NEW=${#NEW_TEMP};
	local TMPLEN_DELTA=$((TMPLEN_NEW - TMPLEN_OLD));

	local SIZE_PREPAYLOAD_OLD;
	read_dword SIZE_PREPAYLOAD_OLD "${FILE}" 3;

	local SIZE_PREPAYLOAD_NEW=$((SIZE_PREPAYLOAD_OLD + (TMPLEN_DELTA * N_PATCHES)));
	write_dword $((SIZE_PREPAYLOAD_NEW)) "${FILE}" 3 5 6;

	sed -i "s|\(mktemp \(-d \)\?\)${OLD_TEMP}|\1${NEW_TEMP}|g" "${FILE}";

	write_dword "$(tail -c52 "${FILE}" | head -c-8 | gzip -c | tail -c8 | head -c4 | hexdump -e '"%u"')" "${FILE}" 1;

	return 0;
}




for BUNDLE in "${@}"; do
	patch_bundle "${OLD_TEMP}" "${NEW_TEMP}" "${BUNDLE}";
done
