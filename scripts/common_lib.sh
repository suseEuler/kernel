ext_subject()
{
	# sed command:
	#       /^Subject: /: finding subject line
	#       :a : set label for code repeat point
	#       $!N : append line into pattern space
	# 	s/\n\s+/ /: check if there is space in the head of next line after Subject line
	#       	if true then \n and space
	#       ta : if above substitution is true, jump to label :a
	#		after substitution fail run below
	#       P : print pattern space
	#       D : clean pattern space
	#       q : stop sed script
	#
	head -10 "$1" | sed -n -E '/^Subject: /{:a ; $!N ; s/\n\s+/ / ; ta ; P ; D; q}' | cut -d " " -f 3-
}

subject_existed()
{
	local subject=$*
	if [ -z "$commits" ]; then
		get_stable_commits
	fi
	echo "$commits" | while read sub; do
		if [[ "$sub" == "$subject" ]]; then
			echo $sub
		fi
	done
}

get_stable_commits()
{
	# $LINUX_STABLE_GIT; #stable tree, 5.10.y branch for OE OLK-5.10
	cd $LINUX_STABLE_GIT
	commits=$(git log --pretty=format:%s $START_STABLE_VERSION..$END_STABLE_VERSION)
	cd - > /dev/null
}
