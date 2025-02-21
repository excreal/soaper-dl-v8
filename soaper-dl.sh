while IFS=' ' read -r ep link; do
    [[ -z "$ep" || -z "$link" ]] && continue
    ep="${ep#[}"
    ep="${ep%]}"
    ...
done < "$_SCRIPT_PATH/$_MEDIA_NAME/$_EPISODE_LINK_LIST"
